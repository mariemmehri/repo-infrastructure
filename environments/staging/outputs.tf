output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "acr_login_server" {
  value = module.acr.acr_login_server
}

output "kubectl_command" {
  value = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${var.cluster_name}"
}

output "argocd_portforward" {
  value = "kubectl port-forward svc/argocd-server -n argocd 9089:80"
}

output "argocd_password" {
  value = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
}