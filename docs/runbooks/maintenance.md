# Maintenance Runbook

## Regular Tasks

### Update Terraform Provider Versions

```bash
# Check current versions
terraform version

# Update lock file
terraform init -upgrade

# Test after update
terraform validate
terraform plan
```

**Frequency:** Monthly

---

### Update ArgoCD Helm Chart

In `modules/argocd/variables.tf`:

```hcl
variable "argocd_chart_version" {
  default = "6.7.3"  <- update this
}
```

Then:
```bash
cd environments/staging
terraform plan  # shows upgrade
terraform apply
```

**Frequency:** When new stable version released

---

### Rotate Azure Credentials

```bash
# Create new service principal secret
az ad sp credential reset \
  --id "" \
  --years 1

# Update GitHub Secrets with new values
# GitHub -> Settings -> Secrets -> Actions
# Update: AZURE_CLIENT_SECRET
```

**Frequency:** Every 6 months minimum

---

### Monitor Azure Costs

```bash
# Check current month spending
az consumption budget list \
  --resource-group "rg-staging-pfe"

# List all resources and their costs
az resource list \
  --resource-group "rg-staging-pfe" \
  --output table
```

**Important:** Destroy staging when not in use to avoid costs.

```bash
cd environments/staging
terraform destroy
```

**Frequency:** Weekly check during PFE

---

### Verify tfstate Health

```bash
# List blobs in tfstate container
az storage blob list \
  --account-name "" \
  --container-name "tfstate" \
  --auth-mode login \
  --output table

# Should show:
# staging.tfstate
# bootstrap-gitops.tfstate
```

**Frequency:** Before any major change
