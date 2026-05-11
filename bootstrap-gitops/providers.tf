terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
  required_version = ">= 1.7.0"
  backend "gcs" {}

}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Récupère les credentials du cluster GKE existant
data "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = "${var.region}-b"
  project  = var.project_id
}
data "google_client_config" "default" {}


# provider "kubernetes" {
#   host = "https://${data.google_container_cluster.gke.endpoint}"

#   client_certificate     = base64decode(data.google_container_cluster.gke.master_auth[0].client_certificate)
#   token                  = data.google_client_config.default.access_token
#   cluster_ca_certificate = base64decode(data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate)
# }

# ----modiffed
provider "kubernetes" {
  host  = "https://${data.google_container_cluster.gke.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate
  )
}

# Provider Helm — cluster déjà créé par Phase A
provider "helm" {
  kubernetes {
    host  = "https://${data.google_container_cluster.gke.endpoint}"
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(
      data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate
    )
  }
}