# terraform {
#   required_providers {
#     google = {
#       source  = "hashicorp/google"
#       version = "~> 5.0"
#     }
#     kubernetes = {
#       source  = "hashicorp/kubernetes"
#       version = "~> 2.27"
#     }
#   }
#   required_version = ">= 1.7.0"
#   backend "gcs" {}

# }

# provider "google" {
#   project = var.project_id
#   region  = var.region
# }

# # Récupère les credentials du cluster GKE existant
# data "google_container_cluster" "gke" {
#   name     = var.cluster_name
#   location = "${var.region}-b"
#   project  = var.project_id
# }
# data "google_client_config" "default" {}


# provider "kubernetes" {
#   host = "https://${data.google_container_cluster.gke.endpoint}"

#   client_certificate     = base64decode(data.google_container_cluster.gke.master_auth[0].client_certificate)
#   token                  = data.google_client_config.default.access_token
#   cluster_ca_certificate = base64decode(data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate)
# }

# bootstrap-gitops/providers.tf

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ─── Lit le cluster GKE existant (créé en Phase A) ────────────
# data source = lecture seule, pas de création
# Garantit que le cluster existe avant de configurer les providers
data "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = "${var.region}-b"
  project  = var.project_id
}

data "google_client_config" "default" {}

# ─── Provider Helm ────────────────────────────────────────────
# Configuré avec les données réelles du cluster existant
# Pas de valeurs dynamiques d'un module en cours de création
provider "helm" {
  kubernetes {
    host  = "https://${data.google_container_cluster.gke.endpoint}"
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(
      data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate
    )
  }
}

# ─── Provider Kubernetes ──────────────────────────────────────
provider "kubernetes" {
  host  = "https://${data.google_container_cluster.gke.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate
  )
}