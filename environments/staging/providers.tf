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
  }
  backend "gcs" {}

}
# Outil pour parler à GCP:crée ressources GCP
provider "google" {
  project = var.project_id
  region  = var.region
}
# exec plugin : token GCP rafraîchi à chaque appel API
# Évite l'expiration du token OAuth2 sur les apply longs
# S'appuie sur le WIF déjà configuré dans GitHub Actions
# Outil pour installer des charts Helm:installe ArgoCD
provider "helm" {
  kubernetes {
    host                   = module.gke.kube_host
    token                  = module.gke.kube_token
    cluster_ca_certificate = base64decode(module.gke.kube_cluster_ca_certificate)
  }
}
# Outil pour parler à Kubernetes (GKE):gère le cluster GKE
provider "kubernetes" {
  host                   = module.gke.kube_host
  token                  = module.gke.kube_token
  cluster_ca_certificate = base64decode(module.gke.kube_cluster_ca_certificate)
}
