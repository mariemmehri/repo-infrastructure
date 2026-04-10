# =============================================================================
# OUTPUTS — Informations utiles après terraform apply
# =============================================================================

output "aks_cluster_name" {
  description = "Nom du cluster AKS"
  value       = module.azure_infra.cluster_name
}

output "acr_login_server" {
  description = "URL du registre ACR"
  value       = module.azure_infra.acr_login_server
}

# Commande à copier-coller pour configurer kubectl
output "kubectl_command" {
  description = "Commande pour connecter kubectl à AKS"
  value       = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${var.cluster_name}"
}

# Commande pour accéder à l'UI ArgoCD via port-forward
output "argocd_portforward_command" {
  description = "Commande pour accéder à l'UI ArgoCD (https://localhost:9089)"
  value       = "kubectl port-forward svc/argocd-server -n argocd 9089:80"
}

# Commande pour récupérer le mot de passe admin ArgoCD
output "argocd_password_command" {
  description = "Commande pour récupérer le mot de passe admin ArgoCD"
  value       = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
}
