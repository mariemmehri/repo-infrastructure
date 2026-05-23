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
  description = "→ GitHub var : GCP_WORKLOAD_PROVIDER (repo infra ET app)"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "terraform_ci_sa_email" {
  description = "→ GitHub var : SERVICE_ACCOUNT_EMAIL (repo infra)"
  value       = google_service_account.terraform_ci.email
}

output "github_actions_sa_email" {
  description = "→ GitHub var : GCP_SERVICE_ACCOUNT (repo app)"
  value       = google_service_account.github_actions_ci.email
}