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
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Récupère les credentials du cluster GKE existant
data "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

provider "kubernetes" {
  host = "https://${data.google_container_cluster.gke.endpoint}"

  client_certificate     = base64decode(data.google_container_cluster.gke.master_auth[0].client_certificate)
  client_key             = base64decode(data.google_container_cluster.gke.master_auth[0].client_key)
  cluster_ca_certificate = base64decode(data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate)
}