# définit les entrées configurables de la stack: nom du groupe de ressources, 
# région, nom du cluster, nombre de nœuds, taille VM, nom de l’ACR.

variable "resource_group_name" {
  description = "Nom du Resource Group Azure"
  type        = string
}

variable "location" {
  description = "Région Azure"
  type        = string
  default     = "Swedencentral"
}

variable "cluster_name" {
  description = "Nom du cluster AKS"
  type        = string
}

variable "node_count" {
  description = "Nombre de nodes AKS"
  type        = number
  default     = 1
}

variable "node_vm_size" {
  description = "Taille des VMs nodes"
  type        = string
  default     = "Standard_D2as_v5"
}

variable "acr_name" {
  description = "Nom du Azure Container Registry"
  type        = string
}