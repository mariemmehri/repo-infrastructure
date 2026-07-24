variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  description = "GCP region for the backup bucket"
  type        = string
  default     = "europe-west1"
}

variable "backup_bucket_name" {
  description = "Globally-unique GCS bucket name for CNPG WAL/base backups (barman-cloud)"
  type        = string
}

variable "ksa_namespace" {
  description = "Kubernetes namespace of the Postgres Cluster's ServiceAccount (must match the CNPG-I barman-cloud plugin wiring in repo-config)"
  type        = string
  default     = "staging"
}

variable "ksa_name" {
  description = "Name of the ServiceAccount CNPG auto-generates for the Cluster, bound to the backup GSA via Workload Identity (must match the Cluster's fullnameOverride in repo-config)"
  type        = string
  default     = "pg-staging"
}
