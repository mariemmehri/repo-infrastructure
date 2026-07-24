output "backup_bucket_name" {
  description = "Name of the GCS bucket CNPG's barman-cloud plugin should back up to"
  value       = google_storage_bucket.cnpg_backup.name
}

output "cnpg_backup_sa_email" {
  description = "Email of the GSA the CNPG-I barman-cloud plugin's KSA impersonates via Workload Identity"
  value       = google_service_account.cnpg_backup.email
}

output "ksa_annotation" {
  description = "Paste as the annotation value on the Kubernetes ServiceAccount referenced by the ObjectStore CR in repo-config"
  value       = "iam.gke.io/gcp-service-account: ${google_service_account.cnpg_backup.email}"
}
