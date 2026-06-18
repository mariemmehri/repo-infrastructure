terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# reste du fichier inchangé...
resource "google_compute_network" "main" {
  name                    = "vpc-${var.environment}-pfe"
  auto_create_subnetworks = false
  project                 = var.project_id

  description = "VPC for ${var.environment} environment - PFE"
}

resource "google_compute_subnetwork" "gke" {
  name          = "subnet-gke-${var.environment}"
  ip_cidr_range = var.gke_subnet_prefix
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.project_id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}