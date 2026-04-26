resource "azurerm_resource_group" "staging" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "staging"
    ManagedBy   = "Terraform"
    Project     = "PFE"
  }
}

module "networking" {
  source              = "../../modules/networking"
  resource_group_name  = azurerm_resource_group.staging.name
  location            = azurerm_resource_group.staging.location
  environment         = "staging"
}

module "acr" {
  source              = "../../modules/acr"
  acr_name            = var.acr_name
  resource_group_name = azurerm_resource_group.staging.name
  location            = azurerm_resource_group.staging.location
  environment         = "staging"
}

module "aks" {
  source              = "../../modules/aks"
  cluster_name        = var.cluster_name
  resource_group_name = azurerm_resource_group.staging.name
  location            = azurerm_resource_group.staging.location
  environment         = "staging"
  node_count          = var.node_count
  node_vm_size        = var.node_vm_size
  aks_subnet_id       = module.networking.aks_subnet_id
  acr_id              = module.acr.acr_id

  depends_on = [module.networking]
}

module "argocd" {
  source                      = "../../modules/argocd"
  kube_host                   = module.aks.kube_host
  kube_client_certificate     = module.aks.kube_client_certificate
  kube_client_key             = module.aks.kube_client_key
  kube_cluster_ca_certificate = module.aks.kube_cluster_ca_certificate

  depends_on = [module.aks]
}