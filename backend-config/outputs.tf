output "resource_group_name" {
  description = "Resource group containing tfstate storage"
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Storage account name - a copier dans backend.hcl"
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Container name"
  value       = azurerm_storage_container.tfstate.name
}
