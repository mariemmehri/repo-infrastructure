
resource "google_artifact_registry_repository" "acr" {
  repository_id = var.acr_name
  location      = var.region
  format        = "DOCKER"
  project       = var.project_id

  description = "Docker registry for ${var.environment} - PFE"

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
}