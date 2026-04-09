output "aks_cluster_name" {
  value = module.azure_infra.cluster_name
}

output "acr_login_server" {
  value = module.azure_infra.acr_login_server
}

output "kubectl_command" {
  value = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${var.cluster_name}"
}
