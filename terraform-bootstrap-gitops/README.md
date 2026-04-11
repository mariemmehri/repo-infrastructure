# Terraform Bootstrap GitOps (Phase B)

Cette stack applique uniquement l'application racine ArgoCD (`apps-root`).

## Pourquoi une stack separee

Le CRD ArgoCD `Application` (`argoproj.io/v1alpha1`) peut ne pas etre pret juste apres l'installation Helm.
Si on cree `kubernetes_manifest` trop tot, Terraform peut echouer avec:

`the server could not find the requested resource (argoproj.io/v1alpha1, Application)`

En separant en 2 phases, on elimine ce risque:

1. **Phase A** (`terraform-todo`) : infra + ArgoCD
2. **Phase B** (`terraform-bootstrap-gitops`) : `apps-root`

## Execution

### 1) Appliquer la phase A

```powershell
Set-Location "c:/Users/wassi/Downloads/stage pfe/terraform-todo"
terraform init
terraform apply -var-file="terraform.tfvars"
```

### 2) Appliquer la phase B

```powershell
Set-Location "c:/Users/wassi/Downloads/stage pfe/terraform-bootstrap-gitops"
terraform init
terraform apply -var-file="terraform.tfvars"
```

## Migration depuis l'ancien mode (si necessaire)

Si `argocd_root_app` etait deja dans l'etat de la phase A, retire-le du state avant de reappliquer la phase A:

```powershell
Set-Location "c:/Users/wassi/Downloads/stage pfe/terraform-todo"
terraform state rm kubernetes_manifest.argocd_root_app
```

Ensuite applique la phase B pour que cette ressource soit geree par le bon state.
