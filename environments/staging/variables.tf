variable "location" {
  type    = string
  default = "swedencentral"
}

variable "resource_group_name" {
  type = string
}

variable "cluster_name" {
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

variable "acr_name" {
  type = string
}