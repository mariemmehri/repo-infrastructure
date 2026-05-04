variable "cluster_name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
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
  description = "Machine type GCP (ex: e2-standard-2)"
  type        = string
  default     = "e2-standard-2"
}

variable "vpc_name" {
  description = "Nom du VPC (équivalent aks_subnet_id sur Azure)"
  type        = string
}

variable "gke_subnet_id" {
  description = "Self-link ou ID du subnet GKE"
  type        = string
}

# variable "acr_id" {
#   description = "ID Artifact Registry (utilisé pour IAM binding)"
#   type        = string
# }