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
# Outil pour parler à GCP:crée ressources GCP
provider "google" {
  project = var.project_id
  region  = var.region
}
# exec plugin : token GCP rafraîchi à chaque appel API
# Évite l'expiration du token OAuth2 sur les apply longs
# S'appuie sur le WIF déjà configuré dans GitHub Actions
provider "helm" {
  kubernetes {
    host                   = module.gke.kube_host
    cluster_ca_certificate = base64decode(module.gke.kube_cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gcloud"
      args = [
        "container", "clusters", "get-credentials",
        var.cluster_name,
        "--region", "${var.region}-b",
        "--project", var.project_id,
        "--quiet",
      ]
    }
  }
}

provider "kubernetes" {
  host = module.gke.kube_host
  cluster_ca_certificate = base64decode(module.gke.kube_cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gcloud"
    args = [
      "container", "clusters", "get-credentials",
      var.cluster_name,
      "--region", "${var.region}-b",
      "--project", var.project_id,
      "--quiet",
    ]
  }
}
