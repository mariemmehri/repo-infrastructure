# Terraform Todo (Phase A)

Cette stack provisionne l'infrastructure Azure de base et installe ArgoCD sur AKS.

## Ce que cette stack cree

- Resource Group Azure
- Azure Kubernetes Service (AKS)
- Azure Container Registry (ACR)
- Role assignment `AcrPull` (AKS -> ACR)
- Namespace Kubernetes `argocd`
- Installation Helm d'ArgoCD

## Fichiers principaux

- `main.tf`: appelle le module `modules/azure-infra`
- `providers.tf`: configure `azurerm`, `kubernetes` et `helm`
- `variables.tf`: variables d'entree de la stack
- `argocd.tf`: namespace + release Helm ArgoCD
- `outputs.tf`: informations utiles apres apply
- `terraform.tfvars`: valeurs de l'environnement

## Variables a renseigner

Dans `terraform.tfvars`:

- `resource_group_name`
- `location`
- `cluster_name`
- `node_count`
- `node_vm_size`
- `acr_name`

## Prerequis

- Terraform installe
- Azure CLI installe
- Connexion Azure active (`az login`)
- Subscription Azure selectionnee

## Execution

```powershell
Set-Location "c:/Users/wassi/Downloads/stage pfe/repo-infrastructure/terraform-todo"
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

## Outputs utiles

- `aks_cluster_name`
- `acr_login_server`
- `kubectl_command`
- `argocd_portforward_command`

Exemple:

```powershell
# Recuperer le kubeconfig
az aks get-credentials --resource-group <rg> --name <cluster>

# Acceder a ArgoCD en local
kubectl port-forward svc/argocd-server -n argocd 9089:80
```

## Notes importantes

- ArgoCD est expose en `ClusterIP` (pas de LoadBalancer public).
- Cette stack doit etre appliquee avant `terraform-bootstrap-gitops`.
- Le module reutilisable Azure est dans `modules/azure-infra`.

## Destruction

```powershell
terraform destroy -var-file="terraform.tfvars"
```
