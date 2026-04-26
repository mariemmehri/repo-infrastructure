# High-Level Architecture Design

## Project Overview

**Project:** Automated Cloud Deployment and Infrastructure Management Platform  
**Type:** PFE (Final Year Project)  
**Stack:** Azure + Terraform + AKS + ACR + ArgoCD + GitHub Actions + Docker + Helm

---

## Global Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                         DEVELOPER                               │
│                    git push → repo-app                          │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   GITHUB ACTIONS (CI)                           │
│                                                                 │
│  1. Build Docker image                                          │
│  2. Run tests                                                   │
│  3. Push image to ACR (tag = commit SHA)                        │
│  4. Update repo-config values-staging.yaml                      │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   REPO-CONFIG (GitOps)                          │
│                                                                 │
│  Helm charts + values-staging.yaml                              │
│  image.tag = <new-commit-sha>                                   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          │ ArgoCD watches
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ARGOCD (CD)                                   │
│                                                                 │
│  Detects change in repo-config                                  │
│  Syncs Helm chart to AKS staging                                │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   AKS STAGING                                   │
│                                                                 │
│  Kubernetes cluster                                             │
│  Runs new application version                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Three Repositories

| Repository | Role | Trigger |
|---|---|---|
| `repo-app` | Application code + Dockerfile + CI | Developer push |
| `repo-config` | Helm charts + values per env | CI updates it |
| `repo-infrastructure` | Terraform + ArgoCD bootstrap | Ops push |

---

## Azure Resources

| Resource | Name | Purpose |
|---|---|---|
| Resource Group | rg-staging-pfe | Contains all staging resources |
| Virtual Network | vnet-staging-pfe | Network isolation for AKS |
| AKS Subnet | subnet-aks-staging | Dedicated subnet for Kubernetes nodes |
| AKS Cluster | aks-staging-pfe | Kubernetes cluster |
| ACR | acrpfestaging | Docker image registry |
| Storage Account | sttfstatepfe | Remote Terraform state |

---

## Terraform Module Structure

```text
modules/
├── networking/    → VNet + AKS subnet
├── aks/           → Kubernetes cluster + AcrPull role
├── acr/           → Container registry
└── argocd/        → ArgoCD via Helm
```

Each module:
- Has a single responsibility
- Exposes inputs via `variables.tf`
- Exposes outputs via `outputs.tf`
- Is documented in `README.md`

---

## Remote Backend

```text
backend-config/
→ creates Azure Blob Storage (once, manually)

environments/staging/
→ reads/writes tfstate from Azure Blob
→ key: staging.tfstate

bootstrap-gitops/
→ reads/writes tfstate from Azure Blob
→ key: bootstrap-gitops.tfstate
```

---

## GitOps Principles Applied

| Principle | Implementation |
|---|---|
| Git = source of truth | All config in Git, nothing manual |
| Declarative | Terraform + Helm = desired state declared |
| CI separate from CD | GitHub Actions (CI) ≠ ArgoCD (CD) |
| Traceability | Image tag = commit SHA |
| Automated sync | ArgoCD auto-syncs on repo change |

---

## Security Principles

| Principle | Implementation |
|---|---|
| No secrets in Git | GitHub Secrets + .gitignore |
| Least privilege | AKS has only AcrPull on ACR |
| Immutable images | Tag = commit SHA, never overwrite |
| State locking | Azure Blob automatic locking |
| No direct Azure access | Only pipeline touches Azure in CI |
