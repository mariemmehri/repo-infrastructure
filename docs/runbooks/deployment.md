# Deployment Runbook

## Prerequisites

- Azure CLI installed and logged in (`az login`)
- Terraform >= 1.0 installed
- kubectl installed
- Helm installed
- Access to GitHub repository

---

## Step 1 — Create Remote Backend (ONCE)

```bash
cd backend-config

cp terraform.tfvars.example terraform.tfvars
# Fill in: storage_account_name (globally unique)

terraform init
terraform plan
terraform apply
```

**Expected output:**
```text
Apply complete! Resources: 3 added
- azurerm_resource_group.tfstate
- azurerm_storage_account.tfstate
- azurerm_storage_container.tfstate
```

**Note the outputs — you will need them for next steps.**

---

## Step 2 — Deploy Staging Infrastructure

```bash
cd environments/staging

cp backend.hcl.example backend.hcl
# Fill in: storage_account_name from Step 1

cp terraform.tfvars.example terraform.tfvars
# Fill in: cluster_name, acr_name, resource_group_name

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

**Expected output:**
```text
Apply complete! Resources: X added
- azurerm_resource_group.staging
- module.networking (VNet + subnet)
- module.acr (container registry)
- module.aks (kubernetes cluster) ← takes 5-10 min
- module.argocd (helm release)
```

---

## Step 3 — Bootstrap GitOps

**Wait for ArgoCD pods to be Running before this step.**

```bash
# Get AKS credentials first
az aks get-credentials \
  --resource-group "rg-staging-pfe" \
  --name "aks-staging-pfe"

# Verify ArgoCD is ready
kubectl get pods -n argocd
# All pods must be Running

# Deploy bootstrap
cd bootstrap-gitops

cp backend.hcl.example backend.hcl
# Fill in: storage_account_name, key = bootstrap-gitops.tfstate

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

**Expected output:**
```text
Apply complete! Resources: 1 added
- kubernetes_manifest.argocd_root_app
```

---

## Step 4 — Verify Deployment

```bash
# Check AKS nodes
kubectl get nodes

# Check ArgoCD pods
kubectl get pods -n argocd

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 9089:80

# Get admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

**Open browser:** http://localhost:9089  
**Login:** admin / `<password from above>`

---

## Destroy Infrastructure

**When you want to stop Azure costs:**

```bash
# Step 1 — destroy bootstrap first
cd bootstrap-gitops
terraform destroy

# Step 2 — destroy staging
cd environments/staging
terraform destroy

# Step 3 — destroy backend (optional — keeps tfstate history)
cd backend-config
terraform destroy
```

---

## Troubleshooting

| Problem | Cause | Solution |
|---|---|---|
| `state blob is already locked` | Another apply running | Wait or break lock manually |
| `CRD not found` on bootstrap | ArgoCD not ready | Wait for pods Running then retry |
| `AcrPull` error | AKS identity not ready | Wait 2 min after AKS creation |
| `terraform init` fails | Wrong backend.hcl values | Check storage account name |
