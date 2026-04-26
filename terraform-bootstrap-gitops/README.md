# Terraform Bootstrap GitOps (Phase B)

Cette stack cree l'application racine ArgoCD `apps-root` dans le namespace `argocd`.

## Objectif

Appliquer la ressource Kubernetes `Application` seulement apres que:

- le cluster AKS existe
- ArgoCD soit installe
- le CRD `argoproj.io/v1alpha1` soit disponible

Ce decoupage evite les erreurs de type ressource non trouvee lors du premier apply.

## Ce que cette stack contient

- `main.tf`: ressource `kubernetes_manifest.argocd_root_app`
- `providers.tf`: providers `azurerm` + `kubernetes`
- `variables.tf`: RG/cluster + source repo de configuration
- `terraform.tfvars`: valeurs de l'environnement

## Variables principales

- `resource_group_name`: Resource Group du cluster AKS
- `cluster_name`: nom du cluster AKS existant
- `config_repo_url`: URL du repo de configuration
- `config_repo_revision`: branche/tag a suivre
- `child_apps_path`: dossier des applications enfants

## Ordre d'execution

1. Appliquer d'abord la Phase A (`terraform-todo`)
2. Appliquer ensuite cette stack Phase B

## Execution

### 1) Phase A

```powershell
Set-Location "c:/Users/wassi/Downloads/stage pfe/repo-infrastructure/terraform-todo"
terraform init
terraform apply -var-file="terraform.tfvars"
```

### 2) Phase B

```powershell
Set-Location "c:/Users/wassi/Downloads/stage pfe/repo-infrastructure/terraform-bootstrap-gitops"
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

## Depannage

Si l'erreur suivante apparait:

`the server could not find the requested resource (argoproj.io/v1alpha1, Application)`

alors ArgoCD/CRD n'est pas encore pret. Refaire un apply de Phase A, attendre quelques minutes, puis reappliquer Phase B.

## Migration depuis l'ancien mode (si necessaire)

Si `argocd_root_app` etait deja gere par la Phase A, retire la ressource du state de la Phase A:

```powershell
Set-Location "c:/Users/wassi/Downloads/stage pfe/repo-infrastructure/terraform-todo"
terraform state rm kubernetes_manifest.argocd_root_app
```

Puis relance l'apply de la Phase B pour que cette ressource soit geree par le bon state.
