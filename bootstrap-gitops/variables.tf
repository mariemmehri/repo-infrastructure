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
  description = "Nom du cluster GKE existant"
  type        = string
}

variable "gitops_repo_url" {
  description = "URL du repo GitOps (config repo)"
  type        = string
}

variable "gitops_target_revision" {
  description = "Branch Git cible"
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Chemin vers les applications ArgoCD dans le repo"
  type        = string
  default     = "apps/"
}