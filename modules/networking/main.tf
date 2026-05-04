resource "google_compute_network" "main" {
  name                    = "vpc-${var.environment}-pfe"
  auto_create_subnetworks = false
  project                 = var.project_id

  description = "VPC for ${var.environment} environment - PFE"
}

resource "google_compute_subnetwork" "aks" {
  name          = "subnet-gke-${var.environment}"
  ip_cidr_range = var.gke_subnet_prefix
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.project_id

  private_ip_google_access = true
}