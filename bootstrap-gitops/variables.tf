# bootstrap-gitops/variables.tf

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
  description = "URL du repo GitOps"
  type        = string
}

variable "gitops_target_revision" {
  description = "Branch Git cible"
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Chemin vers les applications ArgoCD"
  type        = string
  # default     = "apps/"
}

variable "argocd_chart_version" {
  description = "Version du chart Helm ArgoCD"
  type        = string
  default     = "6.7.3"
}