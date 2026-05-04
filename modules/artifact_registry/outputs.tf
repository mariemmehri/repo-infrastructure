output "acr_id" {
  value = google_artifact_registry_repository.acr.id
}

output "acr_login_server" {
  description = "URL complète du registry Docker"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.acr_name}"
}

output "acr_name" {
  value = google_artifact_registry_repository.acr.repository_id
}