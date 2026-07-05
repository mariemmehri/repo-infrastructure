# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

End-to-end GitOps CI/CD platform (PFE — Sopra HR Software) that automatically deploys a full-stack HR Portal (SIRH) app to Google Kubernetes Engine. A `git push` to `main` triggers build → test → image scan → registry push → GitOps config update → ArgoCD sync, with no manual step.

The working tree is a **monorepo of three loosely coupled sub-repositories**, each also pushed independently to its own GitHub repo:

| Local dir | GitHub remote | Role |
|---|---|---|
| `repo-app/` | `mariemmehri/repo-App` | App source (Spring Boot + Angular) + app CI |
| `repo-infrastructure/` | `mariemmehri/repo-infrastructure` | Terraform IaC for GCP + ArgoCD bootstrap |
| `repo-config/` | `mariemmehri/repo-config` | GitOps source of truth (Helm chart + ArgoCD Applications) |

CI workflow variables refer to config as `CONFIG_REPO` / `GITOPS_REPO`; both resolve to `mariemmehri/repo-config`. Each subdirectory has its own `.git`, its own `.github/workflows/`, and its own Git identity — **treat them as independent repos that happen to live together**. A change in one layer never triggers another layer's pipeline (app changes never run Terraform; ArgoCD never touches cloud resources).

## Repository Structure

```
stage pfe/
├── repo-app/            # Spring Boot backend + Angular frontend + docker-compose + CI
├── repo-infrastructure/ # Terraform (GCP infra) + workflow that also bootstraps ArgoCD
└── repo-config/         # Helm chart + ArgoCD App-of-Apps manifests
```

## Common Commands

### Local development (Docker Compose)
```bash
cd repo-app
docker compose up --build
# Frontend: http://localhost:80   Backend API: http://localhost:8081/api/health
```
Nginx proxies `/api/*` → `http://hr-backend:8081`, so the frontend calls relative paths.

### Backend (Spring Boot 3.2.0, Java 17, Maven — `com.example:hr-backend`)
```bash
cd repo-app/backend
mvn verify              # compile + test — exactly what CI runs (mvn verify -q)
mvn spring-boot:run     # run locally without Docker
mvn test -Dtest=ClassName#methodName   # single test
```

### Frontend (Angular 17, Node 20)
```bash
cd repo-app/frontend
npm install --legacy-peer-deps   # --legacy-peer-deps is REQUIRED (Angular 17 peer-dep conflicts)
npm run build                    # ng build --configuration production → dist/hr-frontend/browser
npm start                        # ng serve --host 0.0.0.0
```

### Terraform — staging infra (`repo-infrastructure/environments/staging`)
```bash
cd repo-infrastructure/environments/staging
terraform init \
  -backend-config="bucket=tfstate-pfe-2026" \
  -backend-config="prefix=staging"
terraform fmt -check -recursive    # CI enforces this — always run before committing TF
terraform validate
terraform plan
```
`terraform.tfvars` is written by the workflow at runtime from GitHub vars — locally, copy `terraform.tfvars.example`.

### Terraform — one-time bootstrap (`repo-infrastructure/backend-config`, LOCAL state)
Chicken-and-egg step: creates the GCS state bucket (+ its access-log bucket) and the WIF pool/provider + the two service accounts. Run once per project.
```bash
cd repo-infrastructure/backend-config
terraform init && terraform apply
terraform output workload_identity_provider   # → secret WORKLOAD_IDENTITY_PROVIDER
terraform output terraform_ci_sa_email         # → secret SERVICE_ACCOUNT_EMAIL
terraform output github_actions_sa_email       # → var GCP_SERVICE_ACCOUNT (repo-app repo)
```

### Validate all Terraform modules (matches CI `validate` job)
```bash
cd repo-infrastructure
for d in backend-config environments/staging modules/gke modules/networking modules/artifact_registry modules/iam; do
  (cd "$d" && terraform init -backend=false -input=false && terraform validate)
done
tflint --recursive --format compact
```

### Helm chart (`repo-config`)
```bash
helm lint charts/hr-app
helm template hr-staging charts/hr-app -f charts/hr-app/values.yaml -f charts/hr-app/values-staging.yaml
```

### Access the cluster / ArgoCD UI
```bash
gcloud container clusters get-credentials gke-staging-pfe \
  --region europe-west1-b --project pfe-2026-495220
kubectl port-forward svc/argocd-server -n argocd 9089:80   # http://localhost:9089, user admin
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
# App has no ingress — reach it via port-forward:
kubectl port-forward svc/hr-frontend -n staging 8080:80
```

## Architecture: How the Layers Interact

**App deployment flow** (push to `mariemmehri/repo-App` main — [repo-app/.github/workflows/ci.yml](repo-app/.github/workflows/ci.yml)):
1. `backend-ci`: `mvn verify -q`, uploads the JAR + surefire test report as artifacts.
2. `frontend-ci` (parallel): `npm install --legacy-peer-deps` + `npm run build`, uploads `dist/`.
3. `docker-build-push` (**push events only**, needs both above): downloads the two artifacts, authenticates to GCP via OIDC (no keys), builds both images tagged with the **7-char short SHA** (`${GITHUB_SHA::7}`). The Dockerfiles **do not compile** — they only package the CI-built artifacts ("build once, promote always").
4. **Trivy** scans each image — CRITICAL severity, `ignore-unfixed: true`, `exit-code: 1` → **any CRITICAL CVE blocks the push**.
5. Pushes each image to Google Artifact Registry (`${REGION}-docker.pkg.dev/${PROJECT}/${GAR_REPOSITORY}/...`).
6. **Verifies each tag actually exists in GAR** (`gcloud artifacts docker tags list`) before touching GitOps — avoids deploying a phantom image.
7. Clones `repo-config`, patches `charts/hr-app/values-staging.yaml` with `yq` (`.backend.image.tag` and `.frontend.image.tag`), commits `ci: update image tags to <SHA>`, pushes to `main`.
8. ArgoCD detects the diff and runs `helm upgrade` on GKE (namespace `staging`) with `prune: true` + `selfHeal: true`.

**Infra + bootstrap flow** — one workflow, [repo-infrastructure/.github/workflows/workflow-infra.yml](repo-infrastructure/.github/workflows/workflow-infra.yml), handles Terraform **and** the full ArgoCD lifecycle. There is no separate bootstrap Terraform module.
- Triggers: push/PR on `environments/**`, `modules/**`, `backend-config/**`, the workflow file, or `.checkov.yaml`; daily schedule (13:30 UTC → drift); manual `workflow_dispatch` with `action` = `plan | apply | destroy-staging | drift | bootstrap | unlock`.
- Job graph: `validate` (fmt + validate all modules) → `lint` (tflint) + `security` (checkov, SARIF → Code Scanning) in parallel → `plan` (`-detailed-exitcode`, uploads plan artifact, comments on PRs) → `apply` (applies the *exact* planned binary, gated by GitHub Environment `staging-apply`) → `bootstrap-argocd`.
- **`apply`** ends by fetching GKE credentials and waiting for a node to register and become Ready. `kubectl wait --all` errors with `no matching resources found` on an empty node set, so the step first polls until ≥1 node exists — relevant because the pool uses spot VMs + autoscaling and may briefly have zero registered nodes right after apply.
- **`bootstrap-argocd`**: `helm upgrade --install argocd argo/argo-cd` (chart `6.7.3`) + `kubectl wait` for CRDs/pods, then checks out `repo-config` and `kubectl apply`s `apps/root-app.yaml`. Idempotent — if `namespace argocd` and `application root-app` already exist it skips (~5s), unless `action=bootstrap` forces a reinstall. Runs `if: always()` so it still executes when `apply` is skipped (infra already up to date).
- `detect-drift`: `terraform plan -refresh-only -detailed-exitcode`; opens a GitHub issue labeled `terraform-drift` (deduped against open issues) on real drift.
- `destroy`: strips finalizers from all ArgoCD Applications, uninstalls ArgoCD, force-deletes its CRDs/namespace, then `terraform destroy` — `workflow_dispatch` only, gated by Environment `staging-destroy`.
- `unlock`: reads the GCS lock ID from `staging/default.tflock` and force-unlocks — escape hatch for a stuck lock. (`plan`/`apply` also auto-release the lock on failure.)

**Why bootstrap isn't Terraform:** installing ArgoCD's `Application` CRD via Terraform's `kubernetes_manifest` requires the CRD to already exist at plan time — a sequencing trap. The `bootstrap-argocd` GitHub Actions job (Helm + kubectl) sidesteps it and keeps a single Terraform state (`prefix=staging`) for infra only. The `helm`/`kubernetes` providers remain commented out in [environments/staging/providers.tf](repo-infrastructure/environments/staging/providers.tf) as a record of that decision.

**App-of-Apps (ArgoCD):** [apps/root-app.yaml](repo-config/apps/root-app.yaml) is the root Application. **Its `source.path` MUST be `apps/children`** — that directory holds one child Application per environment ([staging.yaml](repo-config/apps/children/staging.yaml) → namespace `staging`, [dev.yaml](repo-config/apps/children/dev.yaml) → namespace `dev`). If `path` were `apps` instead, ArgoCD would watch the folder containing `root-app.yaml` itself (non-recursive), never create the child Applications, and still report `root-app` Healthy — a silent false-green. Each child app targets the shared chart `charts/hr-app` with a per-env values file, syncs with `prune`/`selfHeal`, and uses `ServerSideApply=true`. `staging.yaml` additionally `ignoreDifferences` on Deployment `/status/terminatingReplicas`.

## Terraform staging composition

[environments/staging/main.tf](repo-infrastructure/environments/staging/main.tf) wires four modules: `networking` (VPC + subnet, private Google access, flow logs) → `iam` (GKE node SA with least-privilege roles + narrow `serviceAccountUser` bindings) → `artifact_registry` → `gke` (`depends_on` networking + iam).

The GKE cluster ([modules/gke/main.tf](repo-infrastructure/modules/gke/main.tf)) is **zonal** in `europe-west1-b` (`${var.region}-b`). Notable, security-hardened settings:
- **Node pool autoscaling IS enabled** — `autoscaling { min_node_count = var.node_count, max_node_count = var.max_node_count }`. Node auto-upgrade + auto-repair on.
- **Spot VMs ARE enabled** (`spot = true`) — nodes can be preempted.
- Workload Identity (`GKE_METADATA`), Shielded nodes (secure boot + integrity monitoring), Calico NetworkPolicy, Binary Authorization (`PROJECT_SINGLETON_POLICY_ENFORCE`), client-certificate auth disabled, default node pool removed and replaced by a dedicated `default` pool.
- `master_authorized_networks` is `0.0.0.0/0` — intentionally open for GitHub Actions' dynamic IPs (tighten post-PFE).

## App details worth knowing

- **Backend has no database** — the app is a mini SIRH (HR) portal: employees, leave requests, and payslips live in in-memory stores under [com.example.hr](repo-app/backend/src/main/java/com/example/hr/), seeded with demo data; data is lost on pod restart. Endpoints: `GET /api/employees`, `GET/POST /api/leaves`, `PUT /api/leaves/{id}/decision`, `GET /api/payslips`, `GET /api/payslips/{id}/download`.
- [HealthController.java](repo-app/backend/src/main/java/com/example/hr/HealthController.java) serves `GET /api/health-check` (K8s readiness/liveness probe target) and `GET /api/health` (explicit status). It carries `@CrossOrigin(origins = "*")`, but in every deployed topology Nginx proxies `/api/*` to the backend so requests are same-origin — CORS never actually fires.

## GCP / Secrets Configuration

Auth is **OIDC Workload Identity Federation** — no JSON service-account keys. WIF pool `github-pool-v2`, provider `github-provider`, scoped by `attribute.repository` so each repo can assume only its own SA:
- `sa-terraform-ci` — used by `workflow-infra.yml` (Terraform + ArgoCD bootstrap; broad infra roles: `container.admin`, `compute.networkAdmin`, `artifactregistry.admin`, `storage.admin`, `iam.serviceAccountAdmin`, `resourcemanager.projectIamAdmin`).
- `sa-github-actions` — used by `repo-app` CI (`artifactregistry.writer`, `container.developer`, `storage.objectViewer`).
- `sa-gke-staging-pfe` — GKE node SA (`artifactregistry.reader`, logging/monitoring writers).

Required GitHub Actions **variables** (`vars.*`): `GCP_PROJECT_ID`, `GCP_REGION`, `GKE_CLUSTER_NAME`, `GAR_REPOSITORY`, `GAR_REPOSITORY_NAME`, `GCS_BUCKET_NAME`, `NODE_COUNT`, `MAX_NODE_COUNT`, `NODE_VM_SIZE`, `GCP_WORKLOAD_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `CONFIG_REPO`, `GITOPS_REPO`.
Required **secrets** (`secrets.*`): `WORKLOAD_IDENTITY_PROVIDER`, `SERVICE_ACCOUNT_EMAIL`, `GH_PAT` (PAT with `contents:write` on `repo-config`).

Concrete current values: project `pfe-2026-495220`, region `europe-west1`, cluster `gke-staging-pfe`, GAR repo `registry-staging-pfe`, state bucket `tfstate-pfe-2026`.

## Terraform State

- Bucket `tfstate-pfe-2026` (GCS, versioning on, keeps 7 newest versions, access-logged to `tfstate-pfe-2026-logs`).
- Prefix `staging` → the only active Terraform root (`environments/staging`); also the state that gates the ArgoCD bootstrap job.
- `backend-config/` uses **local state** (it bootstraps the remote backend). Its `terraform.tfstate` is committed in the working tree.

## Important Constraints

- **`npm install` always needs `--legacy-peer-deps`** (Angular 17 peer-dep conflicts).
- **`terraform fmt -check -recursive` is enforced in CI** — run it before committing any Terraform change.
- **Image tags are the 7-char git SHA**, patched into `values-staging.yaml` automatically — never edit tags there by hand (the next CI push overwrites them).
- **`root-app.yaml` `path` must be `apps/children`** — `apps` silently breaks deployment (see App-of-Apps note).
- **Ingress is disabled** (`ingress.enabled: false`) — the app is only reachable via `kubectl port-forward`; enabling ingress needs an ingress-nginx controller.
- **Checkov gating**: CRITICAL/HIGH hard-fail the pipeline; MEDIUM/LOW/INFO are soft-fail (reported, never block). Skips live in `.checkov.yaml`, each tied to a documented audit item.
- **Trivy blocks the push** on CRITICAL CVEs — if CI fails at scan, patch/upgrade the base images in the Dockerfiles.
- **`modules/iam` grants `iam.serviceAccountUser` narrowly** — only on the env's GKE node SA and the Compute Engine default SA (needed for cluster bootstrap), not project-wide. Don't widen without reason.
- **Spot nodes + autoscaling**: nodes can be preempted and the pool scales between `NODE_COUNT` and `MAX_NODE_COUNT`. If app pods sit `Pending` on `Insufficient cpu`, check `kubectl get events -n staging` and node allocatable — GKE system pods can consume most of a small node; raise `NODE_COUNT`/`MAX_NODE_COUNT`/`NODE_VM_SIZE`.
