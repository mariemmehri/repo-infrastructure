terraform {
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
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "helm" {
  kubernetes {
    host                   = module.gke.kube_host
    token                  = module.gke.kube_token
    cluster_ca_certificate = base64decode(module.gke.kube_cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = module.gke.kube_host
  token                  = module.gke.kube_token
  cluster_ca_certificate = base64decode(module.gke.kube_cluster_ca_certificate)
}