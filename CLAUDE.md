# CLAUDE.md — repo-infrastructure

This file provides guidance to Claude Code when working inside `repo-infrastructure/`.
The parent `../CLAUDE.md` covers the full platform (app, config, CI/CD overview) — read it first for the big picture; this file goes deeper on Terraform module wiring, exact variable defaults, and the infra/ArgoCD-bootstrap workflow internals.

## What this repo is

Terraform IaC for GCP (GKE, VPC, Artifact Registry, IAM, Workload Identity Federation) plus the single GitHub Actions workflow that also bootstraps ArgoCD on the cluster it provisions. No application code, no Helm chart. Two Terraform roots with separate lifecycles and separate state:

| Root | Purpose | State | Run cadence |
|---|---|---|---|
| `backend-config/` | Creates the GCS state bucket + WIF pool/provider + the two CI service accounts | **local** (committed `terraform.tfstate` in this working tree, though gitignored going forward) | once per GCP project (chicken-and-egg bootstrap) |
| `environments/staging/` | VPC, GKE, Artifact Registry, per-env IAM | GCS, `prefix=staging` | every push/PR/schedule/dispatch via `workflow-infra.yml` |

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
│   ├── main.tf                  # wires the 4 modules together
│   ├── providers.tf              # google provider + `backend "gcs" {}` (empty — configured via -backend-config flags); helm/kubernetes providers present but commented out
│   ├── variables.tf
│   ├── outputs.tf                # gke_cluster_name, registry_login_server, kubectl/argocd helper strings
│   ├── backend.hcl.example
│   └── terraform.tfvars.example
├── modules/
│   ├── networking/               # VPC + GKE subnet, no cross-module deps
│   ├── iam/                      # per-env identities: GKE node SA + IAM bindings
│   ├── artifact_registry/        # Docker repo, no cross-module deps
│   └── gke/                      # cluster + node pool; consumes networking + iam outputs
├── .github/workflows/
│   └── workflow-infra.yml        # single workflow: Terraform lifecycle + ArgoCD bootstrap
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
terraform output workload_identity_provider   # -> secret WORKLOAD_IDENTITY_PROVIDER
terraform output terraform_ci_sa_email        # -> secret SERVICE_ACCOUNT_EMAIL
terraform output github_actions_sa_email      # -> var GCP_SERVICE_ACCOUNT (repo-app repo)
```

### Staging infra (`environments/staging/`)
```bash
cd environments/staging
cp terraform.tfvars.example terraform.tfvars   # edit: project_id, cluster_name, registry_name, node_count, max_node_count, node_vm_size
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
for d in backend-config environments/staging modules/gke modules/networking modules/artifact_registry modules/iam; do
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

## Module dependency graph

`environments/staging/main.tf` instantiates four modules. Only two edges are real Terraform dependencies (via `depends_on` or attribute references) — the module block order in the file does **not** imply a serial chain for all four:

```
modules/networking  ──┐
                       ├──> modules/gke  (depends_on = [networking, iam]; consumes
modules/iam         ──┘                  vpc_name, gke_subnet_id, gke_nodes_sa_email)

modules/artifact_registry   (fully independent — no inputs from/outputs to any other module)
```

- **`networking`** — inputs `project_id`, `region`, `environment`; outputs `vpc_id`, `vpc_name`, `gke_subnet_id`. Creates `google_compute_network.main` (`vpc-<env>-pfe`, `auto_create_subnetworks = false`) and `google_compute_subnetwork.gke` (`subnet-gke-<env>`, default CIDR `10.0.1.0/24` via `gke_subnet_prefix`), with `private_ip_google_access = true` and VPC flow logs (`aggregation_interval = INTERVAL_5_SEC`, `flow_sampling = 0.5`, `metadata = INCLUDE_ALL_METADATA`).
- **`iam`** — inputs `project_id`, `environment`, `terraform_ci_sa_email` (built inline in `main.tf` as `sa-terraform-ci@${var.project_id}.iam.gserviceaccount.com`, **not** passed as a module output — `backend-config` and `environments/staging` are separate states with no remote-state data source between them), `developer_group_email` (nullable, default `null`, undocumented in the root CLAUDE.md — when set, grants a Google group `roles/container.clusterViewer`; leave `null` outside staging). Creates `sa-gke-<env>-pfe` with 5 roles (`artifactregistry.reader`, `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `stackdriver.resourceMetadata.writer`), then grants `sa-terraform-ci` `roles/iam.serviceAccountUser` scoped to *only* that SA and to the project's Compute Engine default SA (GKE bootstrap references the default SA even with `remove_default_node_pool = true`). Outputs `gke_nodes_sa_email`, `gke_nodes_sa_name`.
- **`artifact_registry`** — inputs `acr_name`, `project_id`, `region`, `environment`; creates one `google_artifact_registry_repository` (format `DOCKER`); outputs `acr_login_server` = `"${region}-docker.pkg.dev/${project_id}/${acr_name}"` (this is the exact string `repo-app`'s CI builds image references from).
- **`gke`** — see hardening detail below. Inputs include `vpc_name`/`gke_subnet_id` from `networking` and `gke_nodes_sa_email` from `iam`; `depends_on = [module.networking, module.iam]` is set explicitly in `main.tf` even though the attribute references would already force ordering — belt-and-suspenders.

## GKE cluster hardening (`modules/gke/main.tf`)

Zonal cluster in `${var.region}-b` (`europe-west1-b`). The default node pool is removed (`remove_default_node_pool = true`) and replaced by a custom pool that is **also named `default`** (`google_container_node_pool.default`) — don't confuse "the default node pool GCP creates" (removed) with "the node pool resource named `default`" (the one actually running workloads).

Settings, each tagged with the Checkov check ID it satisfies where the code comments one:
- `master_auth.client_certificate_config.issue_client_certificate = false` (CKV_GCP_13) — no client-cert auth, WIF/OIDC only.
- `network_policy { enabled = true, provider = "CALICO" }` (CKV_GCP_65 in the code comment — note `.checkov.yaml` *also* skips `CKV_GCP_65` for a different reason, "RBAC with Google Groups requires Cloud Identity" — same check ID reused for two different findings; don't assume the skip means NetworkPolicy is disabled, it isn't).
- `binary_authorization.evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"` (CKV_GCP_66).
- `master_authorized_networks_config` — single CIDR `0.0.0.0/0` labeled `allow-all` (CKV_GCP_25, which is *also* in the `.checkov.yaml` skip list with a TODO to add `logging_config`— two unrelated things tracked under one check ID again). Open intentionally for GitHub Actions' dynamic runner IPs; tighten post-PFE.
- Workload Identity: `workload_identity_config.workload_pool = "${project_id}.svc.id.goog"` at the cluster level, `workload_metadata_config.mode = "GKE_METADATA"` on both the (unused, pre-removal) default node_config block and the real node pool's node_config.
- Shielded nodes (`enable_secure_boot`, `enable_integrity_monitoring`) set in both node_config blocks (CKV_GCP_68/69/70 in comments).
- `deletion_protection = false` — `terraform destroy` / the `destroy` workflow job can actually tear the cluster down; don't flip this to `true` without also updating the `destroy` job.
- Node pool: `autoscaling { min_node_count = var.node_count, max_node_count = var.max_node_count }` (added in commit `17caae4`, replacing a flat `node_count`), `management { auto_upgrade = true, auto_repair = true }`, `spot = true` (toggled off then back on in commits `4898848`/`dfdf312` while diagnosing a CPU-allocatable problem — kept enabled for staging cost savings, at the cost of preemption risk).
- `release_channel` is validated in `modules/gke/variables.tf` to be `REGULAR` or `STABLE` only (case-insensitive, uppercased); `disk_size_gb` is validated `> 0`. Both are `variables.tf`-level `validation` blocks unique to this module (not present on the `environments/staging` passthrough variables).

Defaults if `terraform.tfvars` omits a value: `node_count=1`, `max_node_count=3`, `node_vm_size="e2-standard-2"`, `disk_size_gb=30`, `release_channel="REGULAR"`, `gke_subnet_prefix="10.0.1.0/24"` (networking module).

## Workflow: `.github/workflows/workflow-infra.yml`

Triggers: push/PR to `main` on paths `environments/**`, `modules/**`, `backend-config/**`, the workflow file itself, `.checkov.yaml`; daily `schedule` (`30 13 * * *` = 13:30 UTC); `workflow_dispatch` with `action` = `plan | apply | destroy-staging | drift | bootstrap | unlock`. `concurrency` group is `terraform-infra-${{ github.ref }}` with `cancel-in-progress: false` — a second push while one run is in flight queues rather than cancels it.

Job graph:
```
validate (fmt -check -recursive + validate, all 6 module dirs, ~30s)
   ├─> lint (tflint --recursive)         ─┐
   └─> security (checkov, console+SARIF)  ├─> plan ─> apply ─> bootstrap-argocd
                                          ─┘
detect-drift   (independent — schedule, or dispatch action=drift)
destroy        (independent — dispatch action=destroy-staging only, env staging-destroy)
unlock         (independent — dispatch action=unlock only)
```

- **`plan`** additionally guards `if:` against running on forked-PR heads (`github.event.pull_request.head.repo.fork == false`) and against `action == 'destroy-staging'`. It writes `terraform.tfvars` at runtime from GitHub `vars.*` (not from any committed file), runs `terraform plan -detailed-exitcode -out=tfplan.binary`, and on a stale-lock failure tries to read the lock ID out of `gs://<bucket>/staging/default.tflock` and `force-unlock` it. Exit code 2 (changes) uploads `tfplan.binary`/`tfplan.json`/`terraform.tfvars` as a 1-day artifact and posts a Create/Update/Destroy table as a PR comment.
- **`apply`** needs `plan` to have exit code `2`, only runs on `push` or `workflow_dispatch(action=apply)` (never on `pull_request`), is gated by GitHub Environment `staging-apply`, downloads the exact `tfplan.binary` from `plan` and applies that binary (never re-plans) — this is what guarantees apply == what was reviewed. After apply it fetches GKE credentials and polls (`for i in 1..30`, 10s sleep) until `kubectl get nodes` returns at least one row before calling `kubectl wait --for=condition=Ready nodes --all --timeout=300s` — added in commit `a0572fe` because `kubectl wait --all` errors out with "no matching resources found" on a zero-node set, which spot VMs + autoscaling make transiently likely right after apply.
- **`bootstrap-argocd`** runs `if: always() && needs.apply.result != 'failure' && needs.plan.result != 'failure'` and not on PRs/destroy — so it still runs when `apply` was skipped because `plan` found no changes (exit code 0). It checks `kubectl get namespace argocd` + `kubectl get application root-app -n argocd`; if both exist and `action != 'bootstrap'` it skips the install (~5s no-op), otherwise `helm upgrade --install argocd argo/argo-cd --version 6.7.3 --namespace argocd --set server.service.type=ClusterIP --wait --timeout 600s`, waits for the `applications.argoproj.io` CRD and the `argocd-server` pod, checks out `vars.GITOPS_REPO` into `repo-config/`, and `kubectl apply -f repo-config/apps/root-app.yaml`.
- **`detect-drift`** — `terraform plan -refresh-only -detailed-exitcode`; on exit 2 opens a GitHub issue labeled `terraform-drift` with the plan log (truncated to 3000 chars), deduped against any already-open issue with that label.
- **`destroy`** — `workflow_dispatch(action=destroy-staging)` only, gated by Environment `staging-destroy`. Strips finalizers from every ArgoCD `Application` (`kubectl patch ... -p '{"metadata":{"finalizers":null}}'`), deletes them, `helm uninstall argocd`, force-deletes the three ArgoCD CRDs and the `argocd` namespace, *then* `terraform destroy -auto-approve`.
- **`unlock`** — reads `staging/default.tflock` from GCS and `terraform force-unlock -force <id>`; a manual escape hatch (`plan`/`apply` also self-heal locks on failure via the same pattern).

Env pinned versions: `TF_VERSION=1.7.5`, `ARGOCD_CHART_VERSION=6.7.3` (`argo/argo-cd` Helm chart), tflint `v0.50.3` (action) vs `.tflint.hcl`'s `google` ruleset plugin `0.27.1` — two different version axes, don't conflate them.

## Checkov gating (`.checkov.yaml`)

`soft-fail-on: [MEDIUM, LOW, INFO]` — only CRITICAL/HIGH hard-fail the pipeline (matches root CLAUDE.md). `download-external-modules: false` (supply-chain guard). Every entry in `skip-check` carries a `TODO [<audit-id>]` comment pointing at the fix; two check IDs are reused for two different unrelated findings each (see GKE hardening section above) — when investigating a skip, read the actual Checkov output, don't assume the code comment on the matching resource is the full story. Current skips: `CKV_GCP_25`, `CKV_GCP_71`, `CKV_GCP_64` (private cluster not enabled), `CKV_GCP_18`, `CKV2_GCP_18` (no explicit firewall rule — relying on implicit VPC defaults), `CKV_GCP_8`/`CKV_GCP_9` (node auto-repair/upgrade — actually **enabled** in `modules/gke/main.tf`'s `management` block; these two skips look stale/redundant since the underlying resource already satisfies them — worth re-checking against a live Checkov run rather than trusting the skip list blindly), `CKV_GCP_41`/`CKV_GCP_49` (`sa-terraform-ci`'s broad `serviceAccountAdmin`/`projectIamAdmin`/project-level `serviceAccountUser`), `CKV_GCP_84` (no CSEK on Artifact Registry), `CKV_GCP_65` (Google-Groups RBAC), `CKV_GCP_62` (tfstate-logs bucket can't log to itself — circular).

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
- **Two Checkov check IDs (`CKV_GCP_25`, `CKV_GCP_65`) each cover two unrelated findings** in this codebase (an inline code comment vs. a separate `.checkov.yaml` skip reason) — verify against actual `checkov` output before assuming a skip means a control is off.
- **Locally-present `terraform.tfvars`/`backend.hcl`/`terraform.tfstate*` files are gitignored, not canonical** — their values (e.g. `node_vm_size = e2-standard-4`, bucket `tfstate-pfe-2026-495220`) may not match the GitHub `vars.*` actually driving CI; check GitHub repo variables for ground truth on live values.
- **`README.md` references an `environments/staging/moved.tf`** ("blocs `moved` — migration state IAM") that does not exist in the current tree — either already deleted post-migration or the README is stale on this point; don't go looking for it.
