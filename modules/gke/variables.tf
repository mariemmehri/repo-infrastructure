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

variable "disk_size_gb" {
  description = "Boot disk size for each GKE node in GB"
  type        = number
  default     = 30

  validation {
    condition     = var.disk_size_gb > 0
    error_message = "disk_size_gb must be greater than 0."
  }
}

variable "release_channel" {
  description = "GKE release channel to use for controlled upgrades"
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["REGULAR", "STABLE"], upper(var.release_channel))
    error_message = "release_channel must be REGULAR or STABLE."
  }
}

variable "vpc_name" {
  description = "Nom du VPC (équivalent aks_subnet_id sur Azure)"
  type        = string
}

variable "gke_subnet_id" {
  description = "Self-link ou ID du subnet GKE"
  type        = string
}

variable "gke_nodes_sa_email" {
  description = "Email of the GKE nodes service account (created by modules/iam)"
  type        = string
}

# variable "acr_id" {
#   description = "ID Artifact Registry (utilisé pour IAM binding)"
#   type        = string
# }