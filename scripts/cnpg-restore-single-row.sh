#!/usr/bin/env bash
#
# Proves that a single accidentally-deleted row in pg-dev (namespace dev) can
# be recovered from its GCS backup, without touching the live pg-dev Cluster
# resource (so ArgoCD's automated sync/selfHeal on cnpg-cluster-dev is never
# fought). Mechanism: on-demand CNPG backup -> restore that backup into a
# throwaway second Cluster (bootstrap.recovery via the barman-cloud CNPG-I
# plugin, same pattern as test-backup-restore.sh's --full-restore-test, just
# retargeted at pg-dev) -> extract the row from the restored copy -> reinsert
# it into live pg-dev -> verify -> tear the throwaway cluster down.
#
# Default mode (--dry-run) never deletes the real row: it captures the
# baseline, backs up, restores into the throwaway cluster, and confirms the
# row is present there — proving the whole recovery path works without
# touching live data. Rehearse with this before recording the real run.
#
# --live actually deletes the chosen row from pg-dev and reinserts it from
# the restored copy — the real drill. Only run this once you've rehearsed
# with --dry-run.
#
# Requires: kubectl, gcloud, jq. The gcloud identity running this must be
# able to setIamPolicy on sa-cnpg-dev-backup@<project>.iam.gserviceaccount.com
# (e.g. roles/iam.serviceAccountAdmin scoped to that SA).

set -euo pipefail

PROJECT_ID="pfe-2026-495220"
GKE_CLUSTER="gke-staging-pfe"
REGION="europe-west1-b"
NAMESPACE="dev"
ORIGINAL_CLUSTER="pg-dev"
BUCKET="cnpg-backup-dev-pfe-2026-495220"
GSA="sa-cnpg-dev-backup@${PROJECT_ID}.iam.gserviceaccount.com"

TABLE="employees"
ROW_WHERE="id = 1"
MODE="dry-run"

usage() {
  cat <<EOF
Usage: $0 [--live] [--table NAME] [--where SQL_CONDITION] [--project ID]

  (no flags)         Dry run: baseline + on-demand backup + restore into a
                     throwaway cluster + verify the row is there. Never
                     touches the real row on pg-dev.
  --live             Real drill: additionally deletes the row from pg-dev
                     and reinserts it from the restored copy.
  --table NAME       Table to test against (default: ${TABLE})
  --where SQL        WHERE clause identifying the one row (default: '${ROW_WHERE}')
  --project ID       Override GCP project (default: ${PROJECT_ID})
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) MODE="live"; shift ;;
    --table) TABLE="$2"; shift 2 ;;
    --where) ROW_WHERE="$2"; shift 2 ;;
    --project) PROJECT_ID="$2"; GSA="sa-cnpg-dev-backup@${PROJECT_ID}.iam.gserviceaccount.com"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

DRILL_START_EPOCH=""
BACKUP_STARTED_EPOCH=""

psql_original() {
  local pod
  pod=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=${ORIGINAL_CLUSTER},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n "$NAMESPACE" "$pod" -c postgres -- psql -U postgres -d hrapp -tA "$@"
}

psql_restore() {
  local pod
  pod=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=${RESTORE_NAME},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n "$NAMESPACE" "$pod" -c postgres -- psql -U postgres -d hrapp -tA "$@"
}

# Display-only variants (aligned table with headers) for what gets shown on
# screen — psql_original/psql_restore stay unaligned (-tA) so the internal
# baseline/restored-row string comparisons remain exact.
psql_original_pretty() {
  local pod
  pod=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=${ORIGINAL_CLUSTER},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n "$NAMESPACE" "$pod" -c postgres -- psql -U postgres -d hrapp "$@" | sed 's/^/    /'
}

psql_restore_pretty() {
  local pod
  pod=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=${RESTORE_NAME},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n "$NAMESPACE" "$pod" -c postgres -- psql -U postgres -d hrapp "$@" | sed 's/^/    /'
}

# ---------------------------------------------------------------------------
# Preflight
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

  log "Fetching GKE credentials for ${GKE_CLUSTER} (${REGION})..."
  gcloud container clusters get-credentials "$GKE_CLUSTER" --region "$REGION" --project "$PROJECT_ID" >/dev/null

  local current_context
  current_context=$(kubectl config current-context)
  [[ "$current_context" == *"$GKE_CLUSTER"* ]] || {
    echo "unexpected kubectl context '${current_context}', expected one referencing ${GKE_CLUSTER}" >&2
    exit 1
  }

  for crd in clusters.postgresql.cnpg.io backups.postgresql.cnpg.io objectstores.barmancloud.cnpg.io; do
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

  log "Row under test: SELECT * FROM ${TABLE} WHERE ${ROW_WHERE};"
}

# ---------------------------------------------------------------------------
# Throwaway restore cluster: create, teardown
# ---------------------------------------------------------------------------

RUN_SUFFIX=""
RESTORE_NAME=""
RECOVERY_OBJSTORE_NAME=""
NETPOL_NAME=""
BACKUP_NAME=""

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

  log "Cleanup done."
  exit "$exit_code"
}

# ---------------------------------------------------------------------------
# Main drill
# ---------------------------------------------------------------------------

run_drill() {
  log "Mode: ${MODE}"

  log "Step 1/7 — Baseline: capturing the row from ${ORIGINAL_CLUSTER}..."
  local baseline
  baseline=$(psql_original -c "SELECT * FROM ${TABLE} WHERE ${ROW_WHERE};")
  [[ -n "$baseline" ]] || { echo "no row matches '${ROW_WHERE}' in ${TABLE} — pick a row that exists" >&2; exit 1; }
  log "Baseline row:"
  psql_original_pretty -c "SELECT * FROM ${TABLE} WHERE ${ROW_WHERE};"

  RUN_SUFFIX="$(printf '%s-%04x' "$(date +%Y%m%d%H%M%S)" "$((RANDOM % 65536))")"
  RESTORE_NAME="pg-dev-restore-test-${RUN_SUFFIX}"
  RECOVERY_OBJSTORE_NAME="${RESTORE_NAME}-recovery"
  NETPOL_NAME="postgres-cnpg-${RESTORE_NAME}"
  BACKUP_NAME="ondemand-restore-test-${RUN_SUFFIX}"
  log "Run ID: ${RUN_SUFFIX} (all created resources labeled created-by=cnpg-restore-single-row.sh,run-id=${RUN_SUFFIX})"

  trap cleanup EXIT

  log "Step 2/7 — Triggering on-demand backup ${BACKUP_NAME} (guarantees the row is in a fresh backup)..."
  BACKUP_STARTED_EPOCH=$(date +%s)
  kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: ${BACKUP_NAME}
  namespace: ${NAMESPACE}
  labels:
    created-by: cnpg-restore-single-row.sh
    run-id: "${RUN_SUFFIX}"
spec:
  cluster:
    name: ${ORIGINAL_CLUSTER}
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
  CREATED_BACKUP=true

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
  [[ "$phase" == "completed" ]] || { echo "backup ${BACKUP_NAME} never completed (last phase: ${phase:-<none>})" >&2; exit 1; }
  log "Backup completed."

  if [[ "$MODE" == "live" ]]; then
    log "Step 3/7 — Deleting the row from ${ORIGINAL_CLUSTER} (simulated accidental data loss)..."
    DRILL_START_EPOCH=$(date +%s)
    psql_original -c "DELETE FROM ${TABLE} WHERE ${ROW_WHERE};"
    log "Row deleted. Proof — the same query now returns nothing on ${ORIGINAL_CLUSTER}:"
    local gone_check
    gone_check=$(psql_original -c "SELECT * FROM ${TABLE} WHERE ${ROW_WHERE};")
    if [[ -z "$gone_check" ]]; then
      echo "    (0 rows — data is really gone)"
    else
      echo "    UNEXPECTED: row still present: $gone_check" >&2
      exit 1
    fi
  else
    log "Step 3/7 — [dry-run] Skipping deletion on ${ORIGINAL_CLUSTER} — real row is left untouched."
    DRILL_START_EPOCH=$(date +%s)
  fi

  local original_image
  original_image=$(kubectl get cluster "$ORIGINAL_CLUSTER" -n "$NAMESPACE" -o jsonpath='{.status.image}')

  log "Step 4/7 — Restoring the backup into a throwaway cluster ${RESTORE_NAME} (does not touch the live ${ORIGINAL_CLUSTER} Cluster resource)..."

  kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${NETPOL_NAME}
  namespace: ${NAMESPACE}
  labels:
    created-by: cnpg-restore-single-row.sh
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

  gcloud iam service-accounts add-iam-policy-binding "$GSA" \
    --project "$PROJECT_ID" --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${RESTORE_NAME}]" >/dev/null
  CREATED_IAM_BINDING=true

  kubectl apply -f - <<EOF
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: ${RECOVERY_OBJSTORE_NAME}
  namespace: ${NAMESPACE}
  labels:
    created-by: cnpg-restore-single-row.sh
    run-id: "${RUN_SUFFIX}"
spec:
  configuration:
    destinationPath: "gs://${BUCKET}/"
    googleCredentials:
      gkeEnvironment: true
EOF
  CREATED_OBJSTORE=true

  kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${RESTORE_NAME}
  namespace: ${NAMESPACE}
  labels:
    created-by: cnpg-restore-single-row.sh
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
  [[ "$phase" == "Cluster in healthy state" ]] || { echo "restore cluster ${RESTORE_NAME} never became healthy (last phase: ${phase:-<none>})" >&2; exit 1; }
  log "Restore cluster healthy."

  log "Step 5/7 — Extracting the row from the restored copy..."
  local restored_row
  restored_row=$(psql_restore -c "SELECT * FROM ${TABLE} WHERE ${ROW_WHERE};")
  [[ -n "$restored_row" ]] || { echo "FAIL: row missing in restored cluster ${RESTORE_NAME} — restore did not bring the row back" >&2; exit 1; }
  log "Restored row (found inside the throwaway cluster, pulled from the GCS backup):"
  psql_restore_pretty -c "SELECT * FROM ${TABLE} WHERE ${ROW_WHERE};"

  if [[ "$restored_row" != "$baseline" ]]; then
    echo "FAIL: restored row does not match baseline" >&2
    echo "baseline: $baseline" >&2
    echo "restored: $restored_row" >&2
    exit 1
  fi
  log "PASS: restored row matches baseline."

  if [[ "$MODE" == "live" ]]; then
    log "Step 6/7 — Reinserting the row into live ${ORIGINAL_CLUSTER}..."
    local restore_pod
    restore_pod=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=${RESTORE_NAME},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
    local orig_pod
    orig_pod=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=${ORIGINAL_CLUSTER},cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n "$NAMESPACE" "$restore_pod" -c postgres -- \
      psql -U postgres -d hrapp -c "\\copy (SELECT * FROM ${TABLE} WHERE ${ROW_WHERE}) TO STDOUT" \
      | kubectl exec -i -n "$NAMESPACE" "$orig_pod" -c postgres -- \
      psql -U postgres -d hrapp -c "\\copy ${TABLE} FROM STDIN"

    log "Step 7/7 — Verifying the row is back in ${ORIGINAL_CLUSTER}..."
    local final_row
    final_row=$(psql_original -c "SELECT * FROM ${TABLE} WHERE ${ROW_WHERE};")
    log "Live query against ${ORIGINAL_CLUSTER} right now:"
    kubectl exec -n "$NAMESPACE" "$orig_pod" -c postgres -- psql -U postgres -d hrapp -c "SELECT * FROM ${TABLE} WHERE ${ROW_WHERE};" | sed 's/^/    /'
    [[ "$final_row" == "$baseline" ]] || { echo "FAIL: row in ${ORIGINAL_CLUSTER} after reinsert does not match baseline" >&2; exit 1; }
    log "PASS: row is back in ${ORIGINAL_CLUSTER}, identical to baseline."

    local drill_end_epoch rto rpo
    drill_end_epoch=$(date +%s)
    rto=$(( drill_end_epoch - DRILL_START_EPOCH ))
    rpo=$(( DRILL_START_EPOCH - BACKUP_STARTED_EPOCH ))
    log "RTO (deletion -> row verified back): ${rto}s"
    log "RPO (backup start -> deletion, i.e. max data possibly at risk): ${rpo}s"
  else
    log "Step 6-7/7 — [dry-run] Skipped: no deletion happened, so nothing to reinsert or verify on the live cluster."
    log "Dry run passed. Re-run with --live to perform the real drill (deletes and reinserts a real row on pg-dev)."
  fi
  # trap-driven cleanup runs on exit, tearing down the throwaway cluster and its companions.
}

preflight
run_drill
