# repo-infrastructure — PFE GitOps Platform

## Architecture

- **backend-config/** : Crée le Storage Account Azure (tfstate)
- **modules/** : Modules réutilisables (aks, acr, networking, argocd)
- **environments/staging/** : Environnement staging
- **bootstrap-gitops/** : Bootstrap ArgoCD apps-root

## Ordre de déploiement

### 1. Backend

```bash
cd backend-config
terraform init
terraform apply
```

### 2. Infrastructure staging

```bash
cd environments/staging
terraform init -backend-config=backend.hcl
terraform apply
```

### 3. Bootstrap GitOps

```bash
cd bootstrap-gitops
terraform init -backend-config=backend.hcl
terraform apply
```
