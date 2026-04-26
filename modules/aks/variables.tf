variable "cluster_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "environment" {
  type = string
}

variable "node_count" {
  type    = number
  default = 1
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D2as_v5"
}

variable "aks_subnet_id" {
  type = string
}

variable "acr_id" {
  type = string
}

# ← NOUVEAU
variable "service_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

# ← NOUVEAU
variable "dns_service_ip" {
  type    = string
  default = "10.1.0.10"
}