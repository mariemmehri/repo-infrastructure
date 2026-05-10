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

variable "registry_name" {
  description = "Nom du repository Artifact Registry"
  type        = string
}
variable "argocd_chart_version" {
  description = "Version du chart ArgoCD à installer"
  type        = string
  default     = "6.7.3"
}