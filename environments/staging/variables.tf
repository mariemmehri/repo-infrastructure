variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west1"
}

variable "cluster_name" {
  description = "Nom du cluster GKE"
  type        = string
}

variable "node_count" {
  description = "Nombre de nodes GKE"
  type        = number
  default     = 1
}

variable "node_vm_size" {
  description = "Machine type GCP"
  type        = string
  default     = "e2-standard-2"
}

variable "disk_size_gb" {
  description = "Boot disk size for GKE nodes in GB"
  type        = number
  default     = 30
}

variable "release_channel" {
  description = "GKE release channel"
  type        = string
  default     = "REGULAR"
}

variable "registry_name" {
  description = "Nom du repository Artifact Registry"
  type        = string
}
