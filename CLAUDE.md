# CLAUDE.md — repo-infrastructure

This file provides guidance to Claude Code when working inside `repo-infrastructure/`.
The parent `../CLAUDE.md` covers the full platform (app, config, CI/CD overview) — read it first for the big picture; this file goes deeper on Terraform module wiring, exact variable defaults, and the infra/ArgoCD-bootstrap workflow internals.

## What this repo is

Terraform IaC for GCP (GKE, VPC, Artifact Registry, IAM, Workload Identity Federation) plus the single GitHub Actions workflow that also bootstraps ArgoCD on the cluster it provisions. No application code, no Helm chart. Two Terraform roots with separate lifecycles and separate state:

| Root | Purpose | State | Run cadence |
|---|---|---|---|
| `backend-config/` | Creates the GCS state bucket + WIF pool/provider + the two CI service accounts | **local** (committed `terraform.tfstate` in this working tree, though gitignored going forward) | once per GCP project (chicken-and-egg bootstrap) |
| `environments/staging/` | VPC, GKE, Artifact Registry, CNPG backup buckets, per-env IAM | GCS, `prefix=staging` | every push/PR/dispatch via `workflow-infra.yml` (no schedule trigger — removed, see workflow section) |

There is no `environments/prod` or `environments/dev` — `staging` is the only root that exists, matching the rest of the platform.

## Directory Structure

```
repo-infrastructure/
├── backend-config/              # One-time bootstrap — local state
│   ├── main.tf                  # tfstate GCS bucket + its access-log bucket
│   ├── wif.tf                   # WIF pool/provider + sa-terraform-ci + sa-github-actions
│   ├── variables.tf
│   ├── outputs.tf                # values to paste into GitHub secrets/vars
│   └── terraform.tfvars.example
├── environments/staging/        # Only active Terraform root
│   ├── main.tf                  # wires 8 module blocks together (5 module sources — networking, iam, gke, artifact_registry, cnpg_backup — with artifact_registry doubled for prod (`790d472`) and cnpg_backup tripled for staging/dev/prod (`c1037fe`/`6d89ca2`))
│   ├── providers.tf              # google provider + `backend "gcs" {}` (empty — configured via -backend-config flags); helm/kubernetes providers present but commented out
│   ├── variables.tf
│   ├── outputs.tf                # gke_cluster_name, registry_login_server, prod_registry_login_server, cnpg_backup_bucket_name[_dev|_prod], cnpg_backup_sa_email[_dev|_prod], kubectl/argocd helper strings
│   ├── backend.hcl.example
│   └── terraform.tfvars.example
├── modules/
│   ├── networking/               # VPC + GKE subnet, no cross-module deps
│   ├── iam/                      # per-env identities: GKE node SA + IAM bindings
│   ├── artifact_registry/        # Docker repo, no cross-module deps; instantiated twice (staging + prod registries)
│   ├── gke/                      # cluster + node pool; consumes networking + iam outputs
│   └── cnpg_backup/              # CNPG barman-cloud backup bucket + dedicated GSA; instantiated 3x (staging/dev/prod), no cross-module deps
├── .github/workflows/
│   └── workflow-infra.yml        # single workflow: Terraform lifecycle + ArgoCD bootstrap
├── scripts/
│   └── test-backup-restore.sh    # CNPG backup/restore verification for pg-staging; read-only health-check by default, --full-restore-test opt-in (mutates IAM + spins up a throwaway cluster)
├── .checkov.yaml                 # severity gating + documented skip list
└── .tflint.hcl                   # google ruleset plugin + a few core rules
```

`terraform.tfvars`, `backend.hcl`, and `*.tfstate*` are all gitignored (`.gitignore`) — what you see committed is only the `.example` files. Locally-present `terraform.tfvars`/`backend.hcl`/`terraform.tfstate*` files in this working tree are leftover local-run artifacts, not tracked state; don't treat their contents (e.g. a `tfstate-pfe-2026-495220` bucket name or `node_vm_size = e2-standard-4`) as necessarily the canonical/current values — cross-check against GitHub vars if it matters.

## Common Commands

### One-time bootstrap (`backend-config/`, local state)
```bash
cd backend-config
cp terraform.tfvars.example terraform.tfvars   # edit: project_id, bucket_name, github_owner, github_infra_repo, github_app_repo
terraform init
terraform apply
# Note: variables.tf requires github_owner/github_infra_repo/github_app_repo (no
# defaults — used to scope each SA's WIF binding to its own repo), but the committed
# terraform.tfvars.example only has project_id/region/bucket_name; add the three
# GitHub-related lines yourself after copying, don't expect to find them to "edit".
terraform output workload_identity_provider   # -> secret WORKLOAD_IDENTITY_PROVIDER
terraform output terraform_ci_sa_email        # -> secret SERVICE_ACCOUNT_EMAIL
terraform output github_actions_sa_email      # -> var GCP_SERVICE_ACCOUNT (repo-app repo)
```

### Staging infra (`environments/staging/`)
```bash
cd environments/staging
cp terraform.tfvars.example terraform.tfvars   # edit: project_id, cluster_name, registry_name, node_count, max_node_count, node_vm_size,
                                                #       cnpg_backup_bucket_name, cnpg_backup_bucket_name_dev, cnpg_backup_bucket_name_prod
terraform init \
  -backend-config="bucket=tfstate-pfe-2026" \
  -backend-config="prefix=staging"
terraform fmt -check -recursive    # CI enforces this
terraform validate
terraform plan
```
Note: the `backend "gcs" {}` block in `providers.tf` is intentionally empty — bucket/prefix are always supplied via `-backend-config` flags (locally from `backend.hcl`, in CI from GitHub vars), never hardcoded.

### Validate every module (mirrors CI `validate` job)
```bash
for d in backend-config environments/staging modules/gke modules/networking modules/artifact_registry modules/iam modules/cnpg_backup; do
  (cd "$d" && terraform init -backend=false -input=false -no-color && terraform validate -no-color)
done
```

### Lint / security scan locally
```bash
terraform fmt -recursive
tflint --recursive --format compact              # plugin "google" v0.27.1; CI pins tflint v0.50.3
checkov -d . --framework terraform --config-file .checkov.yaml
```

### Post-apply cluster access
```bash
gcloud container clusters get-credentials gke-staging-pfe --region europe-west1-b --project pfe-2026-495220
kubectl port-forward svc/argocd-server -n argocd 9089:80
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

### CNPG backup/restore verification (`scripts/test-backup-restore.sh`)
Added `6b77c38`. Hardcodes `pg-staging`/`gke-staging-pfe`/`staging` — not parameterized per-environment beyond the `--project`/`--namespace` flags.
```bash
./scripts/test-backup-restore.sh                    # read-only: Cluster health, last backup, WAL archiving, bucket reachability — no mutation
./scripts/test-backup-restore.sh --full-restore-test # opt-in: seeds a canary row, backs up, restores into a throwaway second Cluster, verifies, tears down
```
`--full-restore-test` mutates IAM (a temporary Workload Identity binding) and creates real cluster resources for its duration; requires `roles/iam.serviceAccountAdmin` scoped to `sa-cnpg-staging-backup@<project>.iam.gserviceaccount.com`, which a regular user account does not get by default.

## Module dependency graph

`environments/staging/main.tf` instantiates **eight module blocks** from **five distinct module sources**: `artifact_registry` is instantiated twice (staging + prod registries, since `790d472`), and `cnpg_backup` is instantiated three times (staging/dev/prod, since `c1037fe`/`6d89ca2`). Only two edges are real Terraform dependencies (via `depends_on` or attribute references) — the module block order in the file does **not** imply a serial chain:

```
modules/networking  ──┐
                       ├──> modules/gke  (depends_on = [networking, iam]; consumes
modules/iam         ──┘                  vpc_name, gke_subnet_id, gke_nodes_sa_email)

module.artifact_registry        (staging registry — fully independent, no inputs from/outputs to any other module)
module.artifact_registry_prod   (prod registry — same module source, second instantiation; also fully independent)
module.cnpg_backup               (staging CNPG backup bucket + GSA — fully independent)
module.cnpg_backup_dev           (same module source, second instantiation, env=dev — fully independent)
module.cnpg_backup_prod          (same module source, third instantiation, env=prod — fully independent)
```

- **`networking`** — inputs `project_id`, `region`, `environment`; outputs `vpc_id`, `vpc_name`, `gke_subnet_id`. Creates `google_compute_network.main` (`vpc-<env>-pfe`, `auto_create_subnetworks = false`) and `google_compute_subnetwork.gke` (`subnet-gke-<env>`, default CIDR `10.0.1.0/24` via `gke_subnet_prefix`), with `private_ip_google_access = true` and VPC flow logs (`aggregation_interval = INTERVAL_5_SEC`, `flow_sampling = 0.5`, `metadata = INCLUDE_ALL_METADATA`).
- **`iam`** — inputs `project_id`, `environment`, `terraform_ci_sa_email` (built inline in `main.tf` as `sa-terraform-ci@${var.project_id}.iam.gserviceaccount.com`, **not** passed as a module output — `backend-config` and `environments/staging` are separate states with no remote-state data source between them), `developer_group_email` (nullable, default `null`, undocumented in the root CLAUDE.md — when set, grants a Google group `roles/container.clusterViewer`; leave `null` outside staging). Creates `sa-gke-<env>-pfe` with 5 roles (`artifactregistry.reader`, `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `stackdriver.resourceMetadata.writer`), then grants `sa-terraform-ci` `roles/iam.serviceAccountUser` scoped to *only* that SA and to the project's Compute Engine default SA (GKE bootstrap references the default SA even with `remove_default_node_pool = true`). Outputs `gke_nodes_sa_email`, `gke_nodes_sa_name`.
- **`artifact_registry`** — inputs `acr_name`, `project_id`, `region`, `environment`; creates one `google_artifact_registry_repository` (format `DOCKER`); outputs `acr_login_server` = `"${region}-docker.pkg.dev/${project_id}/${acr_name}"` (this is the exact string `repo-app`'s CI builds image references from). The root module wires it up **twice**: `module.artifact_registry` (`acr_name = var.registry_name`, `environment = "staging"`) for the normal dev/staging build path, and `module.artifact_registry_prod` (`acr_name = var.prod_registry_name`, default `"registry-prod-pfe"`, `environment = "prod"`) — a registry only ever written to by `promote-prod.yml`'s `crane copy` step, never by regular CI builds. `environments/staging/outputs.tf` exposes both as `registry_login_server` and `prod_registry_login_server`. Neither the `apply` nor `destroy` job's runtime-generated `terraform.tfvars` sets `prod_registry_name`, so it always resolves to its `"registry-prod-pfe"` default — there is no `GAR_PROD_REPOSITORY`-style GitHub var feeding this Terraform root (that var, if present, is consumed on `repo-app`'s side, not here).
- **`gke`** — see hardening detail below. Inputs include `vpc_name`/`gke_subnet_id` from `networking` and `gke_nodes_sa_email` from `iam`; `depends_on = [module.networking, module.iam]` is set explicitly in `main.tf` even though the attribute references would already force ordering — belt-and-suspenders.
- **`cnpg_backup`** (new since `c1037fe`) — inputs `project_id`, `environment`, `region`, `backup_bucket_name`, `ksa_namespace` (default `"staging"`), `ksa_name` (default `"pg-staging"`); creates one `google_storage_bucket` (WAL/base-backup destination for CNPG's barman-cloud CNPG-I plugin, `force_destroy = false`, **`lifecycle { prevent_destroy = true }`** — added in `82fae62`), a dedicated `sa-cnpg-<env>-backup` GSA (deliberately separate from the GKE node SA — "one SA per purpose"), two bucket-scoped IAM bindings (`roles/storage.objectAdmin` for writes, `roles/storage.legacyBucketReader` because `objectAdmin` alone lacks the `storage.buckets.get` that barman-cloud's preflight check needs — added in `11387fd`), and a `google_service_account_iam_member` Workload Identity binding letting the CNPG Cluster's KSA (`<ksa_namespace>/<ksa_name>`) impersonate the GSA with no downloaded key. Outputs `backup_bucket_name`, `cnpg_backup_sa_email`, `ksa_annotation`. Root module wires it up **three times** — `module.cnpg_backup` (staging, `ksa_namespace`/`ksa_name` default to `staging`/`pg-staging`), `module.cnpg_backup_dev` (`ksa_namespace="dev"`, `ksa_name="pg-dev"`), `module.cnpg_backup_prod` (`ksa_namespace="prod"`, `ksa_name="pg-prod"`) — mirroring the `artifact_registry`/`artifact_registry_prod` double-instantiation pattern, one bucket+GSA per environment. `environments/staging/outputs.tf` exposes all three as `cnpg_backup_bucket_name[_dev|_prod]` / `cnpg_backup_sa_email[_dev|_prod]`. The actual CNPG operator/`Cluster`/CNPG-I plugin wiring that consumes these buckets and GSAs lives in `repo-config`, not here. **Important operational trap:** because the backup buckets carry `prevent_destroy = true`, a `terraform destroy` of `environments/staging` (the `destroy` workflow job) will hard-fail on all three `google_storage_bucket.cnpg_backup` resources unless they're first removed from state (`terraform state rm`) or the lifecycle block is temporarily dropped — the `destroy` job as currently written does not special-case this and will error out on that step.
- **`google_compute_global_address.ingress_ip`** (new — no dedicated module, just a `for_each` over `["dev", "staging", "prod"]` directly in `main.tf`, since it's three near-identical one-line resources) — reserves one **global** static IP per app environment (`ip-hr-dev`/`ip-hr-staging`/`ip-hr-prod`), consumed by `repo-config`'s `charts/hr-app/templates/ingress.yaml` via the `kubernetes.io/ingress.global-static-ip-name` annotation (the exact resource name must match `ingress.staticIpName` in each `values-<env>.yaml`, Terraform doesn't enforce that cross-repo agreement). Global, not regional, because GKE's native Ingress controller provisions a Google **external Application Load Balancer**, which is global. Exposed via `output "ingress_ips"` (map of env → IP address). Fully independent of every other module/resource here.

## GKE cluster hardening (`modules/gke/main.tf`)

Zonal cluster in `${var.region}-b` (`europe-west1-b`). The default node pool is removed (`remove_default_node_pool = true`) and replaced by a custom pool that is **also named `default`** (`google_container_node_pool.default`) — don't confuse "the default node pool GCP creates" (removed) with "the node pool resource named `default`" (the one actually running workloads). The cluster also sets `enable_intranode_visibility = true` (not tied to a code-commented Checkov ID, but present in the resource) and `networking_mode = "VPC_NATIVE"` with an empty `ip_allocation_policy {}` block (GKE auto-assigns secondary ranges).

Settings, each tagged with the Checkov check ID it satisfies where the code comments one:
- `master_auth.client_certificate_config.issue_client_certificate = false` (CKV_GCP_13) — no client-cert auth, WIF/OIDC only.
- **NetworkPolicy is now enforced via Dataplane V2, not Calico** — `datapath_provider = "ADVANCED_DATAPATH"` (Cilium/eBPF), which is mutually exclusive at the GKE API level with the legacy `network_policy { enabled = true, provider = "CALICO" }` addon block that used to be here (that block is gone from the code). Switched deliberately because Calico/iptables cannot enforce an egress `NetworkPolicy` against a Service `ClusterIP` (only against pod IPs, pre-DNAT) — see `repo-config`'s `docs/issues-rencontrees.md` Issue 4. Checkov's `CKV_GCP_12` only recognizes the legacy Calico block, so it's now in the `.checkov.yaml` skip list with a comment explaining Dataplane V2 satisfies the intent that check can't see — don't read that skip as "NetworkPolicy enforcement is off," it isn't. (The `CKV_GCP_65` skip that used to double up with a code comment on this same block no longer does — see Checkov section below, only `CKV_GCP_25` still covers two unrelated findings.)
- `binary_authorization.evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"` (CKV_GCP_66).
- `master_authorized_networks_config` — single CIDR `0.0.0.0/0` labeled `allow-all` (CKV_GCP_25, which is *also* in the `.checkov.yaml` skip list with a TODO to add `logging_config`— two unrelated things tracked under one check ID again). Open intentionally for GitHub Actions' dynamic runner IPs; tighten post-PFE.
- Workload Identity: `workload_identity_config.workload_pool = "${project_id}.svc.id.goog"` at the cluster level, `workload_metadata_config.mode = "GKE_METADATA"` on both the (unused, pre-removal) default node_config block and the real node pool's node_config.
- Shielded nodes (`enable_secure_boot`, `enable_integrity_monitoring`) set in both node_config blocks (CKV_GCP_68/69/70 in comments).
- `deletion_protection = false` — `terraform destroy` / the `destroy` workflow job can actually tear the cluster down; don't flip this to `true` without also updating the `destroy` job.
- **`spot = true` is now set on both node_config blocks** — the real node pool's (as before) and, since `bfc1d33`, the cluster's own (unused, pre-removal) default `node_config` block too. Toggled off then back on in commits `4898848`/`dfdf312` while diagnosing a CPU-allocatable problem — kept enabled for staging cost savings, at the cost of preemption risk.
- Node pool: `autoscaling { min_node_count = var.node_count, max_node_count = var.max_node_count }` (added in commit `17caae4`, replacing a flat `node_count`) plus an explicit `initial_node_count = var.node_count` (added in `82fae62`), `management { auto_upgrade = true, auto_repair = true }`.
- `release_channel` is validated in `modules/gke/variables.tf` to be `REGULAR` or `STABLE` only (case-insensitive, uppercased); `disk_size_gb` is validated `> 0`. Both are `variables.tf`-level `validation` blocks unique to this module (not present on the `environments/staging` passthrough variables).

Defaults if `terraform.tfvars` omits a value: `node_count=1`, `max_node_count=3`, `node_vm_size="e2-standard-2"`, `disk_size_gb=30`, `release_channel="REGULAR"`, `gke_subnet_prefix="10.0.1.0/24"` (networking module), `prod_registry_name="registry-prod-pfe"` (`environments/staging/variables.tf`, feeds `module.artifact_registry_prod`), `cnpg_ksa_namespace="staging"`/`cnpg_ksa_name="pg-staging"` (feed `module.cnpg_backup`, must stay in sync with the CNPG Cluster's `fullnameOverride` in `repo-config`). **No default** for `cnpg_backup_bucket_name`, `cnpg_backup_bucket_name_dev`, `cnpg_backup_bucket_name_prod` — each must be an explicitly-set, globally-unique GCS bucket name or `terraform plan`/`apply` fails; CI supplies these from `vars.CNPG_BACKUP_BUCKET_NAME[_DEV|_PROD]`.

## Workflow: `.github/workflows/workflow-infra.yml`

Triggers: push/PR to `main` on paths `environments/**`, `modules/**`, `backend-config/**`, the workflow file itself, `.checkov.yaml`; `workflow_dispatch` with `action` = `plan | apply | destroy-staging | bootstrap` (the `workflow_dispatch.inputs.action` description comment and its `options:` list still show an older `plan | apply | destroy-staging | drift | bootstrap | unlock` — that line is commented out/stale, the live `options:` array no longer includes `drift` or `unlock`). **The daily `schedule` trigger (`30 13 * * *` = 13:30 UTC) is fully commented out** (`2bb1607 "delete schedule"`) — there is currently no cron-triggered run at all, not even a plan-only one; `on.schedule` is entirely absent from the live YAML, just two commented-out lines. `concurrency` group is `terraform-infra-${{ github.ref }}` with `cancel-in-progress: false` — a second push while one run is in flight queues rather than cancels it.

**There is no `detect-drift` job and no working `unlock` job anymore.** Commit `fa8b32c` ("fix:delete drift") deleted the entire `detect-drift` job (107 lines removed) rather than disabling it, and commits `5413dea`/`db7d786` ("delete unlock"/"deleted unlock") commented out the whole `unlock` job block — its YAML is still physically present at the bottom of the file but entirely inside `#` comments, so it does not run and doesn't even parse as a job. With the schedule trigger now also gone entirely, this workflow only ever runs on `push`, `pull_request`, or `workflow_dispatch` — there is no unattended periodic execution of any kind (plan-only or otherwise).

Job graph (current):
```
validate (fmt -check -recursive + validate, all 7 module dirs incl. modules/cnpg_backup, ~30s)
   ├─> lint (tflint --recursive)         ─┐
   └─> security (checkov, console+SARIF)  ├─> plan ─> apply ─> bootstrap-argocd
                                          ─┘
destroy        (independent — dispatch action=destroy-staging only, env staging-destroy)
```

- **`plan`** additionally guards `if:` against running on forked-PR heads (`github.event.pull_request.head.repo.fork == false`) and against `action == 'destroy-staging'`. It writes `terraform.tfvars` at runtime from GitHub `vars.*` (not from any committed file, and without setting `prod_registry_name` — that var keeps its `"registry-prod-pfe"` default) — the runtime-written tfvars now also includes `cnpg_backup_bucket_name`, `cnpg_backup_bucket_name_dev`, `cnpg_backup_bucket_name_prod` from `vars.CNPG_BACKUP_BUCKET_NAME[_DEV|_PROD]`, since those three have no Terraform default and would otherwise fail `plan`. Runs `terraform plan -detailed-exitcode -out=tfplan.binary`, and on a stale-lock failure tries to read the lock ID out of `gs://<bucket>/staging/default.tflock` and `force-unlock` it. Exit code 2 (changes) uploads `tfplan.binary`/`tfplan.json`/`terraform.tfvars` as a 1-day artifact and posts a Create/Update/Destroy table as a PR comment.
- **`apply`** needs `plan` to have exit code `2`, only runs on `push` or `workflow_dispatch(action=apply)` (never on `pull_request`), is gated by GitHub Environment `staging-apply`, downloads the exact `tfplan.binary` from `plan` and applies that binary (never re-plans) — this is what guarantees apply == what was reviewed. After apply it fetches GKE credentials and polls (`for i in 1..30`, 10s sleep) until `kubectl get nodes` returns at least one row before calling `kubectl wait --for=condition=Ready nodes --all --timeout=300s` — added in commit `a0572fe` because `kubectl wait --all` errors out with "no matching resources found" on a zero-node set, which spot VMs + autoscaling make transiently likely right after apply.
- **`bootstrap-argocd`** `needs: [plan, apply]`, runs `if: always() && needs.apply.result != 'failure' && needs.plan.result != 'failure' && github.event_name != 'pull_request' && (github.event_name != 'workflow_dispatch' || inputs.action != 'destroy-staging')` — so it still runs when `apply` was skipped because `plan` found no changes (exit code 0), but not on PRs or a `destroy-staging` dispatch. It checks `kubectl get namespace argocd` + `kubectl get application root-app -n argocd`; if both exist and `action != 'bootstrap'` it skips the install (~5s no-op), otherwise creates the `argocd` namespace, `helm repo add argo ... --force-update`, `helm upgrade --install argocd argo/argo-cd --version 6.7.3 --namespace argocd --set server.service.type=ClusterIP --wait --timeout 600s`, waits for the `applications.argoproj.io` CRD and the `argocd-server` pod, checks out `vars.GITOPS_REPO` into `repo-config/`, and `kubectl apply -f repo-config/apps/root-app.yaml`.
- **`destroy`** — `workflow_dispatch(action=destroy-staging)` only, gated by Environment `staging-destroy`. Writes the same runtime `terraform.tfvars` as `plan` (including the three `cnpg_backup_bucket_name*` vars). **New step, added in `1565367`, runs *before* the ArgoCD cleanup**: strips finalizers from every `clusters.postgresql.cnpg.io` CR across all namespaces and deletes them. This has to happen first and separately from the ArgoCD `Application` finalizer-stripping below — the CNPG `Cluster` CR carries its own finalizer, set/cleared by the CNPG operator itself, distinct from the ArgoCD `resources-finalizer.argocd.argoproj.io` finalizer on the `Application` object that wraps it (e.g. `cnpg-cluster-staging`). If the `cnpg-operator` Application (running the operator pod) gets deleted before the `Cluster`'s own finalizer is cleared, no operator is left alive to process it and the `Cluster` hangs in `Terminating` forever — this is exactly what previously produced `timed out waiting for the condition on applications/cnpg-cluster-staging` while every other Application deleted cleanly. Only after that does it strip finalizers from every ArgoCD `Application` (`kubectl patch ... -p '{"metadata":{"finalizers":null}}'`), delete them, `helm uninstall argocd`, force-delete the three ArgoCD CRDs and the `argocd` namespace, *then* `terraform destroy -auto-approve`. **This last step will currently fail** on the three `google_storage_bucket.cnpg_backup` resources (staging/dev/prod) because of their `lifecycle { prevent_destroy = true }` (see `cnpg_backup` module note above) — the job has no step that removes them from state or overrides the lifecycle first.
- **No standalone `unlock` job runs anymore** (see above — its block is fully commented out). The escape hatch that remains live is the "Release lock on failure" step inline in both `plan` and `apply`: on failure they read `staging/default.tflock` from GCS and `terraform force-unlock -force <id>`. If that self-heal step itself fails to clear a lock, there is currently no dispatchable job to fall back on short of uncommenting the `unlock` block or running `terraform force-unlock` manually.

Env pinned versions: `TF_VERSION=1.7.5`, `ARGOCD_CHART_VERSION=6.7.3` (`argo/argo-cd` Helm chart), tflint `v0.50.3` (action) vs `.tflint.hcl`'s `google` ruleset plugin `0.27.1` — two different version axes, don't conflate them.

## Checkov gating (`.checkov.yaml`)

`soft-fail-on: [MEDIUM, LOW, INFO]` — only CRITICAL/HIGH hard-fail the pipeline (matches root CLAUDE.md). `download-external-modules: false` (supply-chain guard). Every entry in `skip-check` carries a `TODO [<audit-id>]` or `SKIP` comment pointing at the fix or the reasoning; one check ID (`CKV_GCP_25`) is still reused for two different unrelated findings (see GKE hardening section above — the `CKV_GCP_65` code-comment/skip-list duality that used to exist alongside it is gone now that the Calico `network_policy` block was removed) — when investigating a skip, read the actual Checkov output, don't assume the code comment on the matching resource is the full story. Current skips: `CKV_GCP_25`, `CKV_GCP_71`, `CKV_GCP_64` (private cluster not enabled), `CKV_GCP_18`, `CKV2_GCP_18` (no explicit firewall rule — relying on implicit VPC defaults), `CKV_GCP_8`/`CKV_GCP_9` (node auto-repair/upgrade — actually **enabled** in `modules/gke/main.tf`'s `management` block; these two skips look stale/redundant since the underlying resource already satisfies them — worth re-checking against a live Checkov run rather than trusting the skip list blindly), `CKV_GCP_41`/`CKV_GCP_49` (`sa-terraform-ci`'s broad `serviceAccountAdmin`/`projectIamAdmin`/project-level `serviceAccountUser`), `CKV_GCP_84` (no CSEK on Artifact Registry), `CKV_GCP_65` (Google-Groups RBAC), `CKV_GCP_62` (tfstate-logs bucket can't log to itself — circular). Two skips added alongside the recent `cnpg_backup`/Dataplane V2 work: `CKV_GCP_78` (the `cnpg_backup` module's bucket has no GCS versioning/lifecycle rule — deliberate, since barman-cloud manages its own backup retention and a GCS lifecycle rule here would fight Barman's own object pruning) and `CKV_GCP_12` (Checkov only recognizes the legacy Calico `network_policy{enabled=true}` addon block for NetworkPolicy enforcement; this cluster now enforces it via Dataplane V2's `datapath_provider = "ADVANCED_DATAPATH"`, which the check doesn't know how to see — see GKE hardening section).

## WIF / service accounts (`backend-config/wif.tf`)

One WIF pool (`github-pool-v2`) and provider (`github-provider`, OIDC issuer `https://token.actions.githubusercontent.com`), scoped project-wide by `attribute_condition = "assertion.repository_owner == '<github_owner>'"`, then narrowed per-SA by a `principalSet://.../attribute.repository/<owner>/<repo>` binding — `sa-terraform-ci` binds only `<owner>/repo-infrastructure`, `sa-github-actions` (created here but used by `repo-app`'s CI, not this repo's workflow) binds only `<owner>/repo-app`. `attribute_mapping` maps `google.subject`, `attribute.repository`, `attribute.ref`.

- `sa-terraform-ci` project roles: `container.admin`, `compute.networkAdmin`, `artifactregistry.admin`, `storage.admin`, `iam.serviceAccountAdmin`, `resourcemanager.projectIamAdmin`. Notably **not** granted `iam.serviceAccountUser` at project scope here — that's deliberately added narrowly by `modules/iam` per environment (on the env's GKE node SA and the Compute Engine default SA only), which is what `CKV_GCP_49`'s skip comment is flagging as an open item (the broad admin roles above still trip other checks).
- `sa-github-actions` project roles: `artifactregistry.writer`, `container.developer`, `storage.objectViewer`. (Root CLAUDE.md's app-CI section describes this SA's usage from `repo-app`'s side.)
- APIs enabled here as a side effect: `iamcredentials.googleapis.com`, `sts.googleapis.com`, `artifactregistry.googleapis.com` (all `disable_on_destroy = false`).

## Terraform state specifics

- `backend-config/main.tf` creates the bucket named by `var.bucket_name` plus a `${bucket_name}-logs` bucket; both have `uniform_bucket_level_access = true`, `public_access_prevention = "enforced"`, versioning on; the main bucket has a `lifecycle_rule` deleting versions beyond the 7 newest and logs access to the `-logs` bucket.
- `environments/staging/providers.tf` declares `backend "gcs" {}` with no arguments — bucket/prefix must always come from `-backend-config=` flags (CI writes them from `vars.GCS_BUCKET_NAME` / literal `"staging"`; locally from `backend.hcl`, copied from `backend.hcl.example`).
- `backend-config/` itself intentionally stays on local state (the bootstrap-the-bootstrapper problem) — its `.tfstate`/`.tfstate.backup` files are gitignored but currently present untracked in this working tree from local runs; treat them as disposable, not source of truth.
- `.gitignore` excludes `backend.hcl`, `terraform.tfvars`, `*.tfstate`, `*.tfstate.*`, `.terraform/`, `crash.log`, `*.tfplan`, `tfplan.*` — only `.tfvars.example`/`backend.hcl.example` are meant to be committed.

## Key Constraints

- **Only `environments/staging` is a live root** — no `dev`/`prod` environments exist; don't create `environments/prod` without also standing up its own state prefix, IAM, and workflow gating.
- **`terraform fmt -check -recursive` is enforced in `validate`** — run it before committing.
- **`apply` always applies the artifact `plan` produced**, never a fresh plan — if you need to change a var between plan and apply, that must happen in a new push, not by editing the downloaded plan.
- **The node pool resource is literally named `default`**, distinct from (and a replacement for) the GKE-imposed default pool that `remove_default_node_pool = true` deletes.
- **`master_authorized_networks_config` is `0.0.0.0/0`** — a real open API surface, kept for GitHub Actions' dynamic IPs; don't "fix" this without also solving the runner-IP-allowlisting problem (e.g. self-hosted runners or a NAT gateway with a fixed egress IP).
- **Spot VMs (`spot = true`) can be preempted at any time** — this was toggled off/on twice while chasing a CPU-allocatable issue (`4898848` → `dfdf312`) before autoscaling was added (`17caae4`); if pods go `Pending` on `Insufficient cpu`, check node allocatable before assuming it's a spot preemption.
- **`modules/iam`'s `terraform_ci_sa_email` input is a hand-built string** (`sa-terraform-ci@${project_id}.iam.gserviceaccount.com`), not a cross-state reference to `backend-config`'s output — if the account name in `backend-config/wif.tf` ever changes, this string in `environments/staging/main.tf` must be updated in lockstep, Terraform will not catch the drift.
- **`bootstrap-argocd` runs on `always()`** — it is not gated on `apply` actually having run; its own `already_bootstrapped` check is what keeps repeat runs cheap. Don't add a stricter `needs`/`if` without preserving the "run even when apply was skipped" behavior.
- **One Checkov check ID (`CKV_GCP_25`) covers two unrelated findings** in this codebase (an inline code comment on `master_authorized_networks_config` vs. a separate `.checkov.yaml` skip reason about `logging_config`) — verify against actual `checkov` output before assuming a skip means a control is off. (`CKV_GCP_65` used to have the same duality tied to the now-removed Calico `network_policy` block; it's just a single Google-Groups-RBAC skip now.)
- **Locally-present `terraform.tfvars`/`backend.hcl`/`terraform.tfstate*` files are gitignored, not canonical** — their values (e.g. `node_vm_size = e2-standard-4`, bucket `tfstate-pfe-2026-495220`) may not match the GitHub `vars.*` actually driving CI; check GitHub repo variables for ground truth on live values.
- **`README.md` references an `environments/staging/moved.tf`** ("blocs `moved` — migration state IAM") that does not exist in the current tree — either already deleted post-migration or the README is stale on this point; don't go looking for it.
- **`environments/staging` now provisions 8 module blocks from 5 distinct sources, not 4** — commit `790d472` added `module.artifact_registry_prod` (same `modules/artifact_registry` source, `acr_name = var.prod_registry_name`, default `"registry-prod-pfe"`, `environment = "prod"`); commits `c1037fe`/`6d89ca2` added `module.cnpg_backup`/`cnpg_backup_dev`/`cnpg_backup_prod` (new `modules/cnpg_backup` source, one bucket+GSA per environment). All five extra blocks are fully independent of `networking`/`iam`/`gke`. `artifact_registry_prod` exists purely as the destination of `promote-prod.yml`'s `crane copy`; nothing in this repo's Terraform or `workflow-infra.yml` writes to it or reads `GAR_PROD_REPOSITORY` — that variable, if it exists, is consumed on `repo-app`'s side.
- **The `cnpg_backup` module's three backup buckets carry `lifecycle { prevent_destroy = true }`** (added `82fae62`) — a real `terraform destroy` of `environments/staging` (the `destroy` workflow job) will hard-fail on those three `google_storage_bucket` resources; the job doesn't remove them from state or override the lifecycle first. If you actually need to tear down a backup bucket, do it explicitly (`terraform state rm` + manual `gcloud storage buckets delete`, or a targeted lifecycle override) — don't expect a plain `destroy-staging` dispatch to succeed end-to-end while these exist.
- **`destroy`'s CNPG-Cluster-finalizer-stripping step (added `1565367`) must run before the ArgoCD Application cleanup, not after** — the CNPG `Cluster` CR has its own operator-managed finalizer, separate from the ArgoCD `Application`'s finalizer wrapping it. Deleting the `cnpg-operator` Application first leaves no operator alive to clear the `Cluster`'s finalizer, and it hangs in `Terminating` forever. Don't reorder these steps.
- **NetworkPolicy enforcement moved from Calico to Dataplane V2** (`d2b328a`) — `modules/gke/main.tf` no longer sets `network_policy { enabled = true, provider = "CALICO" }`; it sets `datapath_provider = "ADVANCED_DATAPATH"` instead (Cilium/eBPF), because Calico/iptables can't enforce egress `NetworkPolicy` against a Service `ClusterIP`. This required a full cluster recreate. Checkov's `CKV_GCP_12` (added to the skip list) only recognizes the old Calico block — don't read that skip as NetworkPolicy being off.
- **`detect-drift` no longer exists, `unlock` no longer runs, and the daily `schedule` trigger is now fully removed** — `fa8b32c` deleted the `detect-drift` job outright (not disabled, gone), `5413dea`/`db7d786` fully commented out the `unlock` job block, and `2bb1607` ("delete schedule") commented out the `on.schedule` trigger entirely. The `workflow_dispatch.action` choices are now only `plan | apply | destroy-staging | bootstrap` (the `drift`/`unlock` choices only remain as a stale, commented-out description line). With no schedule trigger left, `workflow-infra.yml` only ever runs on `push`, `pull_request`, or manual `workflow_dispatch` — there is no unattended periodic run of any kind anymore (not even a drift-detecting or plan-only one). If you need scheduled drift detection or a dispatchable lock-release job back, both must be re-added from scratch — don't assume either still fires because the YAML for the lock-release logic *looks* intact inline in `plan`/`apply`.
