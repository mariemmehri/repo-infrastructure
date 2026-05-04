output "bucket_name" {
  description = "GCS bucket name - à copier dans backend.hcl"
  value       = google_storage_bucket.tfstate.name
}

output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}