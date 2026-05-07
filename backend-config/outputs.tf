output "bucket_name" {
  description = "GCS bucket name - à copier dans backend.hcl"
  value       = google_storage_bucket.tfstate.name
}

output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}


# ─── Nouveaux — valeurs à copier dans les secrets GitHub ────
output "workload_identity_provider" {
  description = "→ secret GitHub : WORKLOAD_IDENTITY_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "→ secret GitHub : SERVICE_ACCOUNT_EMAIL"
  value       = google_service_account.terraform_ci.email
}