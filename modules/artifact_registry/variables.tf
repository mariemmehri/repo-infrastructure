variable "acr_name" {
  description = "Nom du repository Artifact Registry"
  type        = string
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "Région GCP"
  type        = string
}

variable "environment" {
  description = "Nom de l'environnement"
  type        = string
}