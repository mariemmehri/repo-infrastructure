terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

locals {
  gke_node_roles = [
    "roles/artifactregistry.reader",             # pull container images
    "roles/logging.logWriter",                   # write app logs to Cloud Logging
    "roles/monitoring.metricWriter",             # write metrics to Cloud Monitoring
    "roles/monitoring.viewer",                   # read monitoring data
    "roles/stackdriver.resourceMetadata.writer", # expose GKE resource metadata
  ]
}

resource "google_service_account" "gke_nodes" {
  account_id   = "sa-gke-${var.environment}-pfe"
  display_name = "GKE Nodes SA - ${var.environment}"
  project      = var.project_id
}

resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset(local.gke_node_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_service_account_iam_member" "terraform_ci_uses_gke_sa" {
  service_account_id = google_service_account.gke_nodes.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.terraform_ci_sa_email}"
}

# Developer kubectl read access — staging only, null in prod skips this resource
resource "google_project_iam_member" "developer_cluster_viewer" {
  count   = var.developer_group_email != null ? 1 : 0
  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "group:${var.developer_group_email}"
}
