# PFE Terraform Infrastructure

This repository contains Infrastructure-as-Code for provisioning a complete GCP-based Kubernetes platform with GitOps automation.

## 📋 Overview

The infrastructure is organized in **phased stacks** to ensure proper dependency ordering:

- **Phase 0**: `backend-config` — Creates GCS bucket for Terraform state & Workload Identity Pool for GitHub Actions auth
- **Phase A**: `environments/staging` — Provisions GKE cluster, networking, artifact registry, and ArgoCD
- **Phase B**: `bootstrap-gitops` — Deploys ArgoCD app-of-apps configuration

## 🗂️ Repository Structure

```
repo-infrastructure/
├── backend-config/           # Phase 0: State bucket + WIF setup
│   ├── main.tf              # GCS bucket, service account, IAM roles
│   ├── wif.tf               # Workload Identity Pool & GitHub provider
│   ├── variables.tf
│   ├── outputs.tf           # Exports: bucket name, WIF provider ID, SA email
│   └── terraform.tfvars
│
├── environments/staging/      # Phase A: GKE + Network + Registry + ArgoCD
│   ├── main.tf              # Calls all modules
│   ├── providers.tf         # GCP, Helm, Kubernetes
│   ├── backend.tf           # GCS remote backend config
│   ├── variables.tf
│   ├── terraform.tfvars
│   └── backend.hcl.example  # Backend config template
│
├── bootstrap-gitops/         # Phase B: ArgoCD bootstrap
│   ├── main.tf              # Application (app-of-apps)
│   ├── providers.tf
│   ├── backend.tf           # GCS remote backend
│   ├── variables.tf
│   └── terraform.tfvars
│
├── modules/                  # Reusable Terraform modules
│   ├── gke/                 # GKE cluster
│   ├── networking/          # VPC, subnets
│   ├── artifact_registry/   # GCP Artifact Registry
│   └── argocd/              # ArgoCD Helm chart
│
└── scripts/                  # Utility scripts
```

## 🔐 Prerequisites

### GCP Setup

1. Create a GCP project
2. Enable required APIs:
   ```bash
   gcloud services enable container.googleapis.com
   gcloud services enable compute.googleapis.com
   gcloud services enable iam.googleapis.com
   gcloud services enable sts.googleapis.com
   gcloud services enable iamcredentials.googleapis.com
   gcloud services enable artifactregistry.googleapis.com
   ```

### GitHub Repository Configuration

#### Secrets (Settings → Secrets and variables → Actions → Secrets)

- `WORKLOAD_IDENTITY_PROVIDER` — Full WIF provider resource ID
  - Format: `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/providers/github-provider`
- `SERVICE_ACCOUNT_EMAIL` — Terraform service account email
  - Format: `sa-terraform-ci@<PROJECT_ID>.iam.gserviceaccount.com`

#### Variables (Settings → Secrets and variables → Actions → Variables)

- `GCP_PROJECT_ID` — Your GCP project ID
- `GCP_REGION` — GCP region (e.g., `europe-west1`)
- `GKE_CLUSTER_NAME` — Name of the GKE cluster to create
- `GCS_BUCKET_NAME` — Name of the GCS bucket for Terraform state
- `GITOPS_REPO_URL` — URL of your GitOps repository (for ArgoCD)
- `GITOPS_PATH` — Path within GitOps repo (e.g., `environments/staging`)

## 🚀 Getting Started

### 1. Local Setup

```bash
# Clone and navigate
git clone <repo-url>
cd repo-infrastructure

# Configure gcloud
gcloud config set project <YOUR_PROJECT_ID>
gcloud auth application-default login
```

### 2. Create Terraform Variables File

Copy the example and fill in values:

```bash
# Phase 0: backend-config
cd backend-config
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Phase A: environments/staging
cd ../environments/staging
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
# Edit both files

# Phase B: bootstrap-gitops
cd ../../bootstrap-gitops
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
# Edit both files
```

### 3. Deploy Phase 0 (Backend Config)

```bash
cd backend-config
terraform init
terraform plan
terraform apply
```

This creates:

- GCS bucket for remote state
- Workload Identity Pool for GitHub Actions authentication
- Service account with required IAM roles

**Save the outputs** — you'll need these for GitHub repository secrets:

```bash
terraform output
# Copy workload_identity_provider and service_account_email to GitHub secrets
```

### 4. Deploy Phase A (Infrastructure)

```bash
cd ../environments/staging
terraform init \
  -backend-config="bucket=<your-bucket-name>" \
  -backend-config="prefix=staging" \
  -reconfigure -input=false

terraform plan
terraform apply
```

This creates:

- VPC networking (VPC, subnets, Cloud NAT)
- GKE cluster
- Artifact Registry for container images
- ArgoCD namespace (ready for Phase B)

### 5. Deploy Phase B (GitOps Bootstrap)

```bash
cd ../bootstrap-gitops
terraform init \
  -backend-config="bucket=<your-bucket-name>" \
  -backend-config="prefix=bootstrap" \
  -reconfigure -input=false

terraform plan
terraform apply
```

This deploys:

- ArgoCD application controller
- App-of-Apps configuration pointing to your GitOps repository

## 🔄 CI/CD Workflow

The GitHub Actions workflow (`.github/workflows/ci.yml`) automates the deployment:

### Workflow Phases

1. **terraform-validate** (always runs)
   - Format check: `terraform fmt -check -recursive`
   - Module validation with `-backend=false`

2. **phase-a-infra** (runs on push/manual trigger, not on fork PRs)
   - Authenticates via OIDC (Workload Identity)
   - Runs `terraform init/plan/apply` for `environments/staging`
   - Creates infrastructure

3. **phase-b-gitops** (runs after phase-a succeeds)
   - Authenticates via OIDC
   - Fetches GKE credentials
   - Runs `terraform init/plan/apply` for `bootstrap-gitops`
   - Bootstraps ArgoCD

4. **terraform-destroy** (manual trigger only)
   - Destroys in reverse order (bootstrap-gitops → environments/staging)
   - Protected by GitHub environment approval

### Triggering the Workflow

**Automatic:**

- Push to `main` branch that modifies Terraform files
- PR to `main` (plan only, no apply)

**Manual:**

- Go to Actions → "Terraform CI" → "Run workflow"
- Select action: `plan`, `apply`, or `destroy-staging`
- Select phase: `all`, `phase-a-infra`, `phase-b-gitops`

## 🛠️ Local Development Commands

### Format all Terraform files

```bash
terraform fmt -recursive
```

### Validate all modules

```bash
for d in backend-config environments/staging bootstrap-gitops modules/*; do
  [ -d "$d" ] || continue
  echo "Validating $d"
  (cd "$d" && terraform init -backend=false -input=false && terraform validate)
done
```

### View state

```bash
cd backend-config
terraform state list
terraform state show <resource_name>
```

### Plan with targets (for specific resources)

```bash
cd environments/staging
terraform plan -target=module.gke -out=gke.tfplan
terraform apply gke.tfplan
```

## 🔍 Troubleshooting

### Error: "storage: bucket doesn't exist"

- **Cause**: Backend GCS bucket not created yet
- **Fix**: Run Phase 0 first (`backend-config apply`)

### Error: "Workload Identity Pool already exists"

- **Cause**: Pool exists in GCP but state is desynchronized
- **Fix**:
  ```bash
  cd backend-config
  terraform state rm google_iam_workload_identity_pool.github
  terraform import google_iam_workload_identity_pool.github \
    projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool
  terraform plan
  ```

### Authentication fails in CI

- **Cause**: OIDC secrets not set in GitHub repository
- **Fix**: Verify in repository Settings → Secrets and variables → Actions
  - `WORKLOAD_IDENTITY_PROVIDER` is set
  - `SERVICE_ACCOUNT_EMAIL` is set

### Kubernetes provider fails to authenticate

- **Cause**: GKE cluster not ready or credentials stale
- **Fix**:
  ```bash
  gcloud container clusters get-credentials <cluster-name> \
    --region <region> --project <project-id>
  kubectl cluster-info
  ```

## 📝 Best Practices

1. **Always run `terraform fmt`** before committing
2. **Test locally** before pushing to main
3. **Use `terraform plan`** to review changes before apply
4. **Never commit** `terraform.tfvars` or `backend.hcl` (use `.example` files)
5. **Phase ordering** matters — don't skip phases
6. **State is precious** — back up your `terraform.tfstate` files locally
7. **Use GitHub environments** for prod destroy operations

## 📚 Further Reading

- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [GKE Module Documentation](./modules/gke/README.md)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GitHub OIDC with Terraform](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)

## 📞 Support

For issues or questions:

1. Check the [Troubleshooting](#-troubleshooting) section
2. Review Terraform logs: `export TF_LOG=DEBUG`
3. Inspect GitHub Actions logs in repository
4. Check GCP Cloud Logging for API errors
