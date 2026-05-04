# Service Account dédié pour les nodes GKE
# Equivalent du SystemAssigned Identity AKS
resource "google_service_account" "gke_nodes" {
  account_id   = "sa-gke-${var.environment}-pfe"
  display_name = "GKE Nodes SA - ${var.environment}"
  project      = var.project_id
}

# Permission pour puller les images depuis Artifact Registry
# Equivalent du role assignment AcrPull sur Azure
resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}
data "google_client_config" "default" {}


# Cluster GKE — on désactive le node pool par défaut
# pour le gérer séparément (bonne pratique)
resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = "${var.region}-b"
  project  = var.project_id

  network    = var.vpc_name
  subnetwork = var.gke_subnet_id

  # Supprime le node pool default imposé par GCP
  # On crée le nôtre juste en dessous
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = false
  networking_mode      = "VPC_NATIVE"
  ip_allocation_policy {}

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = {
  environment = var.environment
  managed-by  = "terraform"
}
}

# Node pool séparé — équivalent du default_node_pool AKS
resource "google_container_node_pool" "default" {
  name       = "default"
  cluster    = google_container_cluster.gke.id
  location   = "${var.region}-b"
  node_locations = ["${var.region}-b"]
  project    = var.project_id
  node_count = var.node_count
  autoscaling {
    min_node_count = 1
    max_node_count = 1
  }

  node_config {
    machine_type    = var.node_vm_size
    disk_size_gb    = 30
    service_account = google_service_account.gke_nodes.email
    spot = true
  

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }

  depends_on = [
    google_project_iam_member.artifact_registry_reader
  ]
}