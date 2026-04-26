
#  appelle le module modules/azure-infra et lui passe les paramètres d’environnement:
# resource group, région, nom du cluster, taille des nœuds, registre ACR.
module "azure_infra" {
  source              = "./modules/azure-infra"
  resource_group_name = var.resource_group_name
  location            = var.location
  cluster_name        = var.cluster_name
  node_count          = var.node_count
  node_vm_size        = var.node_vm_size
  acr_name            = var.acr_name
}

