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
  description = "Nombre de nodes GKE (borne basse de l'autoscaling)"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Nombre max de nodes GKE (borne haute de l'autoscaling)"
  type        = number
  default     = 3
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

variable "prod_registry_name" {
  description = "Nom du repository Artifact Registry isolé pour la prod (images promues par tag uniquement)"
  type        = string
  default     = "registry-prod-pfe"
}

variable "developer_group_email" {
  description = "Google group email for developer kubectl read access (staging only, null disables)"
  type        = string
  default     = null
}

variable "cnpg_backup_bucket_name" {
  description = "Globally-unique GCS bucket name for CNPG's barman-cloud WAL/base backups"
  type        = string
}

variable "cnpg_ksa_namespace" {
  description = "Namespace of the Postgres Cluster's ServiceAccount (co-located with repo-app in the staging namespace, not cnpg-system — that's only the operator's namespace)"
  type        = string
  default     = "staging"
}

variable "cnpg_ksa_name" {
  description = "Name of the ServiceAccount CNPG auto-generates for the Cluster (matches the Cluster's fullnameOverride in repo-config's cnpg-cluster-staging.yaml — must stay in sync)"
  type        = string
  default     = "pg-staging"
}

variable "cnpg_backup_bucket_name_dev" {
  description = "Globally-unique GCS bucket name for the dev CNPG cluster's barman-cloud WAL/base backups"
  type        = string
}

variable "cnpg_backup_bucket_name_prod" {
  description = "Globally-unique GCS bucket name for the prod CNPG cluster's barman-cloud WAL/base backups"
  type        = string
}
