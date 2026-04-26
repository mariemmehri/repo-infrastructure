# Disaster Recovery Runbook

## Scenario 1 — tfstate corrupted or lost

**The tfstate is the most critical file.**

### If tfstate is corrupted

```bash
# Azure Blob versioning is enabled
# List previous versions
az storage blob list \
  --account-name "" \
  --container-name "tfstate" \
  --include v \
  --auth-mode login \
  --output table

# Restore previous version
az storage blob copy start \
  --account-name "" \
  --destination-container "tfstate" \
  --destination-blob "staging.tfstate" \
  --source-uri ""
```

### If tfstate is completely lost

```bash
# Import existing resources manually
terraform import azurerm_resource_group.staging /subscriptions//resourceGroups/rg-staging-pfe
terraform import module.aks.azurerm_kubernetes_cluster.aks /subscriptions//resourceGroups/rg-staging-pfe/providers/Microsoft.ContainerService/managedClusters/aks-staging-pfe
```

---

## Scenario 2 — AKS cluster deleted accidentally

```bash
# Re-apply staging environment
cd environments/staging
terraform apply

# Re-apply bootstrap
cd bootstrap-gitops
terraform apply

# ArgoCD will automatically re-sync all applications
```

---

## Scenario 3 — ArgoCD out of sync

```bash
# Manual sync via CLI
argocd app sync apps-root

# Or force sync via UI
# ArgoCD UI → apps-root → Sync → Force
```

---

## Scenario 4 — Pipeline broken, need manual deploy

```bash
# Always possible to deploy manually
cd environments/staging
terraform init -backend-config=backend.hcl
terraform apply

# This is why local backend.hcl is documented
# Pipeline failure never blocks manual recovery
```
