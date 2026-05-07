variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west1"
}

variable "bucket_name" {
  description = "GCS bucket name (globally unique)"
  type        = string
}
# ─── Nouveaux ───────────────────────────────────────────────
variable "github_owner" {
  description = "Nom utilisateur ou organisation GitHub"
  type        = string
}

variable "github_infra_repo" {
  description = "Nom du repo infrastructure (ex: repo-infrastructure)"
  type        = string
}

variable "github_app_repo" {
  description = "Nom du repo application (ex: repo-app)"
  type        = string
}