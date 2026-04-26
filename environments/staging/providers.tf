terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

provider "helm" {
  kubernetes {
    host                   = module.aks.kube_host
    client_certificate     = base64decode(module.aks.kube_client_certificate)
    client_key             = base64decode(module.aks.kube_client_key)
    cluster_ca_certificate = base64decode(module.aks.kube_cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = module.aks.kube_host
  client_certificate     = base64decode(module.aks.kube_client_certificate)
  client_key             = base64decode(module.aks.kube_client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_cluster_ca_certificate)
}