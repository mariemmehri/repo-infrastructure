# Environnement de staging

Cette stack provisionne l'infrastructure GCP utilisée par le déploiement de staging.

## Ce qu'elle crée

- Un réseau VPC et un subnet GKE
- Un Artifact Registry pour les images Docker
- Un cluster GKE connecté au subnet
- Une installation ArgoCD dans le cluster

## Utilisation

​```bash
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
​```