# Bootstrap GitOps

Crée l'Application racine ArgoCD (App of Apps pattern) sur GKE.

## Prérequis

- Cluster GKE déjà provisionné (Sprint F)
- ArgoCD installé sur le cluster (module argocd)
- Repo GitOps configuré

## Utilisation

​```bash
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
​```