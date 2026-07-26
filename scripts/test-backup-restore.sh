#!/usr/bin/env bash
#
# CNPG backup/restore verification for pg-staging (gke-staging-pfe, staging namespace).
#
# Default mode is read-only and makes no changes: it checks Cluster health,
# last backup status, WAL archiving, and bucket reachability.
#
# --full-restore-test additionally proves restore actually works: seeds a
# canary row on the live pg-staging cluster, triggers an on-demand backup,
# restores it into a throwaway second CNPG cluster on the same GKE cluster,
# verifies the canary row is present, then tears everything down (Cluster,
# ObjectStore, NetworkPolicy, IAM binding, Backup CR, canary row). This
# mutates IAM (a temporary Workload Identity binding) and creates real
# cluster resources for the duration of the run, so it is opt-in only.
#
# Requires: kubectl, gcloud, jq. The gcloud identity running --full-restore-test
# must be able to setIamPolicy on sa-cnpg-staging-backup@<project>.iam.gserviceaccount.com
# (e.g. roles/iam.serviceAccountAdmin scoped to that SA) — a regular user
# account is not granted this by default.

set -euo pipefail

PROJECT_ID="pfe-2026-495220"
CLUSTER="gke-staging-pfe"
REGION="europe-west1-b"
NAMESPACE="staging"
ORIGINAL_CLUSTER="pg-staging"
BUCKET="cnpg-backup-staging-pfe-2026-495220"
GSA="sa-cnpg-staging-backup@${PROJECT_ID}.iam.gserviceaccount.com"

MODE="health-check"

usage() {
  cat <<EOF
Usage: $0 [--full-restore-test] [--project ID] [--namespace NS]

  (no flags)            Read-only health check: Cluster status, last backup,
                         WAL archiving, bucket reachability. No mutation.
  --full-restore-test   Full demo: canary row -> on-demand backup -> restore
                         into a throwaway second cluster -> verify -> teardown.
  --project ID          Override GCP project (default: ${PROJECT_ID})
  --namespace NS         Override namespace (default: ${NAMESPACE})
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full-restore-test) MODE="full-restore-test"; shift ;;
    --project) PROJECT_ID="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# ---------------------------------------------------------------------------
# Preflight (both modes)
# ---------------------------------------------------------------------------

preflight() {
  for bin in kubectl gcloud jq; do
    command -v "$bin" >/dev/null || { echo "missing required tool: $bin" >&2; exit 1; }
  done

  local current_project
  current_project=$(gcloud config get-value project 2>/dev/null)
  if [[ "$current_project" != "$PROJECT_ID" ]]; then
    echo "gcloud is pointed at project '$current_project', expected '$PROJECT_ID'" >&2
    exit 1
  fi

  log "Fetching GKE credentials for ${CLUSTER} (${REGION})..."
  gcloud container clusters get-credentials "$CLUSTER" --region "$REGION" --project "$PROJECT_ID" >/dev/null

  for crd in clusters.postgresql.cnpg.io backups.postgresql.cnpg.io scheduledbackups.postgresql.cnpg.io objectstores.barmancloud.cnpg.io; do
    kubectl get crd "$crd" >/dev/null || { echo "missing CRD: $crd — is CNPG + barman-cloud plugin installed?" >&2; exit 1; }
  done

  kubectl get cluster "$ORIGINAL_CLUSTER" -n "$NAMESPACE" >/dev/null || {
    echo "cluster ${ORIGINAL_CLUSTER} not found in namespace ${NAMESPACE}" >&2
    exit 1
  }

  if ! gcloud storage ls "gs://${BUCKET}/" --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "backup bucket gs://${BUCKET}/ is not reachable" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Health-check-only mode
# ---------------------------------------------------------------------------

health_check() {
  log "Cluster phase:"
  kubectl get cluster "$ORIGINAL_CLUSTER" -n "$NAMESPACE" -o jsonpath='{.status.phase}{"\n"}'

  log "Continuous archiving / last backup conditions:"
  kubectl get cluster "$ORIGINAL_CLUSTER" -n "$NAMESPACE" -o json | \
    jq -r '.status.conditions[] | select(.type=="ContinuousArchiving" or .type=="LastBackupSucceeded") | "  \(.type): \(.status) (\(.message))"'

  local schedbackup_name
  schedbackup_name=$(kubectl get scheduledbackup -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$schedbackup_name" ]]; then
    log "Scheduled backup ${schedbackup_name} last/next run:"
    kubectl get scheduledbackup "$schedbackup_name" -n "$NAMESPACE" \
      -o jsonpath='  lastScheduleTime={.status.lastScheduleTime}{"\n"}  nextScheduleTime={.status.nextScheduleTime}{"\n"}'
  else
    echo "  (no ScheduledBackup CR found)" >&2
  fi

  log "Most recent Backup CR:"
  kubectl get backup -n "$NAMESPACE" -o json | \
    jq -r '.items | sort_by(.metadata.creationTimestamp) | last | "name=\(.metadata.name) phase=\(.status.phase) stoppedAt=\(.status.stoppedAt)"' \
    2>/dev/null || echo "  (no Backup CRs found)"

  local objstore_name
  objstore_name=$(kubectl get objectstore -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$objstore_name" ]]; then
    log "ObjectStore ${objstore_name} destination:"
    kubectl get objectstore "$objstore_name" -n "$NAMESPACE" -o jsonpath='{.spec.configuration.destinationPath}{"\n"}'
  else
    echo "  (no ObjectStore CR found)" >&2
  fi

  log "Bucket reachable: gs://${BUCKET}/"
  gcloud storage ls "gs://${BUCKET}/" --project "$PROJECT_ID" >/dev/null && echo "  OK"

  log "Health check complete."
}

# ---------------------------------------------------------------------------
# Full restore test mode
# ---------------------------------------------------------------------------

RUN_SUFFIX=""
RESTORE_NAME=""
RECOVERY_OBJSTORE_NAME=""
NETPOL_NAME=""
BACKUP_NAME=""
CANARY_TOKEN=""

CREATED_CANARY_ROW=false
CREATED_BACKUP=false
CREATED_IAM_BINDING=false
CREATED_NETPOL=false
CREATED_OBJSTORE=false
CREATED_CLUSTER=false

cleanup() {
  local exit_code=$?
  log "--- cleanup (exit code was ${exit_code}) ---"

  if [[ "$CREATED_CLUSTER" == true ]]; then
    log "Deleting restore cluster ${RESTORE_NAME}..."
    kubectl delete cluster "$RESTORE_NAME" -n "$NAMESPACE" --ignore-not-found --wait=true --timeout=120s || true
    kubectl delete pvc -n "$NAMESPACE" -l "cnpg.io/cluster=${RESTORE_NAME}" --ignore-not-found || true
  fi

  if [[ "$CREATED_OBJSTORE" == true ]]; then
    log "Deleting recovery ObjectStore ${RECOVERY_OBJSTORE_NAME}..."
    kubectl delete objectstore "$RECOVERY_OBJSTORE_NAME" -n "$NAMESPACE" --ignore-not-found || true
  fi

  if [[ "$CREATED_NETPOL" == true ]]; then
    log "Deleting NetworkPolicy ${NETPOL_NAME}..."
    kubectl delete networkpolicy "$NETPOL_NAME" -n "$NAMESPACE" --ignore-not-found || true
  fi

  if [[ "$CREATED_IAM_BINDING" == true ]]; then
    log "Removing temporary Workload Identity binding for ${RESTORE_NAME}..."
    gcloud iam service-accounts remove-iam-policy-binding "$GSA" \
      --project "$PROJECT_ID" --role roles/iam.workloadIdentityUser \
      --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${RESTORE_NAME}]" >/dev/null || true
  fi

  if [[ "$CREATED_BACKUP" == true ]]; then
    log "Deleting on-demand Backup CR ${BACKUP_NAME} (GCS objects stay, governed by the 30d retention policy)..."
    kubectl delete backup "$BACKUP_NAME" -n "$NAMESPACE" --ignore-not-found || true
  fi

  if [[ "$CREATED_CANARY_ROW" == true ]]; then
    log "Removing canary row (token ${CANARY_TOKEN}) from ${ORIGINAL_CLUSTER}..."
    local orig_primary
    orig_primary=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=${ORIGINAL_CLUSTER},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$orig_primary" ]]; then
      kubectl exec -n "$NAMESPACE" "$orig_primary" -c postgres -- \
        psql -U postgres -d hrapp -c "DELETE FROM _cnpg_restore_canary WHERE token = '${CANARY_TOKEN}';" || true
    fi
  fi

  log "Cleanup done."
  exit "$exit_code"
}

full_restore_test() {
  # Extra preflight, only relevant to the mutating path.
  local objstore_name
  objstore_name=$(kubectl get objectstore -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')
  if [[ "$objstore_name" != "pg-staging-backups" ]]; then
    log "WARNING: expected ObjectStore name 'pg-staging-backups', found '${objstore_name}' — continuing, but verify this is correct."
  fi

  log "Secret ${ORIGINAL_CLUSTER}-app keys (informational only):"
  kubectl get secret "${ORIGINAL_CLUSTER}-app" -n "$NAMESPACE" -o json | jq -r '.data | keys[]'

  local original_image
  original_image=$(kubectl get cluster "$ORIGINAL_CLUSTER" -n "$NAMESPACE" -o jsonpath='{.status.image}')
  log "Original cluster running image: ${original_image}"

  RUN_SUFFIX="$(printf '%s-%04x' "$(date +%Y%m%d%H%M%S)" "$((RANDOM % 65536))")"
  RESTORE_NAME="pg-restore-test-${RUN_SUFFIX}"
  RECOVERY_OBJSTORE_NAME="${RESTORE_NAME}-recovery"
  NETPOL_NAME="postgres-cnpg-${RESTORE_NAME}"
  BACKUP_NAME="ondemand-restore-test-${RUN_SUFFIX}"
  CANARY_TOKEN="restore-test-${RUN_SUFFIX}"
  log "Run ID: ${RUN_SUFFIX} (all created resources labeled created-by=test-backup-restore.sh,run-id=${RUN_SUFFIX})"

  trap cleanup EXIT

  # 1. Seed canary row on the live original cluster.
  log "Seeding canary row (token ${CANARY_TOKEN}) on ${ORIGINAL_CLUSTER}..."
  local orig_primary
  orig_primary=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=${ORIGINAL_CLUSTER},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n "$NAMESPACE" "$orig_primary" -c postgres -- psql -U postgres -d hrapp -c \
    "CREATE TABLE IF NOT EXISTS _cnpg_restore_canary (token text PRIMARY KEY, inserted_at timestamptz DEFAULT now());"
  kubectl exec -n "$NAMESPACE" "$orig_primary" -c postgres -- psql -U postgres -d hrapp -c \
    "INSERT INTO _cnpg_restore_canary (token) VALUES ('${CANARY_TOKEN}');"
  CREATED_CANARY_ROW=true

  # 2. Trigger an on-demand backup and wait for completion.
  log "Triggering on-demand backup ${BACKUP_NAME}..."
  kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: ${BACKUP_NAME}
  namespace: ${NAMESPACE}
  labels:
    created-by: test-backup-restore.sh
    run-id: "${RUN_SUFFIX}"
spec:
  cluster:
    name: ${ORIGINAL_CLUSTER}
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
  CREATED_BACKUP=true

  log "Waiting for backup to complete..."
  local phase=""
  for i in $(seq 1 30); do
    phase=$(kubectl get backup "$BACKUP_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$phase" == "completed" ]] && break
    if [[ "$phase" == "failed" ]]; then
      echo "backup ${BACKUP_NAME} failed" >&2
      exit 1
    fi
    log "  backup phase=${phase:-<none>} (${i}/30)"
    sleep 10
  done
  if [[ "$phase" != "completed" ]]; then
    echo "backup ${BACKUP_NAME} never completed (last phase: ${phase:-<none>})" >&2
    exit 1
  fi
  log "Backup completed."

  # 3. Companion NetworkPolicy for the restore-test cluster.
  log "Creating companion NetworkPolicy ${NETPOL_NAME}..."
  kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${NETPOL_NAME}
  namespace: ${NAMESPACE}
  labels:
    created-by: test-backup-restore.sh
    run-id: "${RUN_SUFFIX}"
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: ${RESTORE_NAME}
  policyTypes:
    - Ingress
    - Egress
  egress:
    - {}
  ingress:
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 5432
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: cnpg-system
EOF
  CREATED_NETPOL=true

  # 4. Temporary Workload Identity binding for the restore cluster's own KSA.
  log "Granting Workload Identity binding for ${NAMESPACE}/${RESTORE_NAME}..."
  gcloud iam service-accounts add-iam-policy-binding "$GSA" \
    --project "$PROJECT_ID" --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${RESTORE_NAME}]" >/dev/null
  CREATED_IAM_BINDING=true

  # 5. Recovery ObjectStore (read-only, same bucket).
  log "Creating recovery ObjectStore ${RECOVERY_OBJSTORE_NAME}..."
  kubectl apply -f - <<EOF
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: ${RECOVERY_OBJSTORE_NAME}
  namespace: ${NAMESPACE}
  labels:
    created-by: test-backup-restore.sh
    run-id: "${RUN_SUFFIX}"
spec:
  configuration:
    destinationPath: "gs://${BUCKET}/"
    googleCredentials:
      gkeEnvironment: true
EOF
  CREATED_OBJSTORE=true

  # 6. Restore-target Cluster.
  log "Creating restore cluster ${RESTORE_NAME}..."
  kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${RESTORE_NAME}
  namespace: ${NAMESPACE}
  labels:
    created-by: test-backup-restore.sh
    run-id: "${RUN_SUFFIX}"
spec:
  instances: 1
  imageName: "${original_image}"
  storage:
    size: 5Gi
    storageClass: standard-rwo
  serviceAccountTemplate:
    metadata:
      annotations:
        iam.gke.io/gcp-service-account: ${GSA}
  bootstrap:
    recovery:
      source: pluginRecoveryCluster
      database: hrapp
      owner: hrapp
  externalClusters:
    - name: pluginRecoveryCluster
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: ${RECOVERY_OBJSTORE_NAME}
          serverName: "${ORIGINAL_CLUSTER}"
EOF
  CREATED_CLUSTER=true

  log "Waiting for restore cluster to become healthy..."
  phase=""
  for i in $(seq 1 60); do
    phase=$(kubectl get cluster "$RESTORE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$phase" == "Cluster in healthy state" ]] && break
    log "  restore cluster phase=${phase:-<none>} (${i}/60)"
    sleep 10
  done
  if [[ "$phase" != "Cluster in healthy state" ]]; then
    echo "restore cluster ${RESTORE_NAME} never became healthy (last phase: ${phase:-<none>})" >&2
    exit 1
  fi
  log "Restore cluster healthy."

  # 7. Verify the canary row survived the restore.
  log "Verifying canary row in restored cluster..."
  local restore_primary result
  restore_primary=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=${RESTORE_NAME},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
  result=$(kubectl exec -n "$NAMESPACE" "$restore_primary" -c postgres -- \
    psql -U postgres -d hrapp -tAc "SELECT count(*) FROM _cnpg_restore_canary WHERE token = '${CANARY_TOKEN}';")
  if [[ "$result" -ne 1 ]]; then
    echo "FAIL: canary token ${CANARY_TOKEN} missing in restored cluster ${RESTORE_NAME} — restore did not work" >&2
    exit 1
  fi
  log "PASS: canary token ${CANARY_TOKEN} found in restored cluster ${RESTORE_NAME}. Restore verified."
  # trap-driven cleanup runs on exit, tearing down everything created above.
}

# ---------------------------------------------------------------------------

preflight

if [[ "$MODE" == "full-restore-test" ]]; then
  full_restore_test
else
  health_check
fi
