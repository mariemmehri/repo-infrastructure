terraform {
  # ─── Backend distant : stocke le tfstate dans Azure Blob Storage ───────────
  # Remplace ces valeurs par les tiennes AVANT de faire terraform init
  backend "azurerm" {
    resource_group_name  = "rg-todo-app"
    storage_account_name = "acrtodosopra"   # ← ton storage account réel
    container_name       = "tfstate"
    key                  = "todo-app.tfstate"
  }

  required_providers {
    # azurerm → parle à l'API Azure (AKS, ACR, etc.)
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    # helm → installe des charts Helm dans AKS (ArgoCD)
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    # kubernetes → crée des ressources K8s (namespaces, secrets)
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# ─── Provider Azure ───────────────────────────────────────────────────────────
provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# ─── Provider Helm ────────────────────────────────────────────────────────────
# Utilise les outputs INDIVIDUELS du module (plus fiable que kube_config[0])
provider "helm" {
  kubernetes {
    host                   = module.azure_infra.kube_host
    client_certificate     = base64decode(module.azure_infra.kube_client_certificate)
    client_key             = base64decode(module.azure_infra.kube_client_key)
    cluster_ca_certificate = base64decode(module.azure_infra.kube_cluster_ca_certificate)
  }
}

# ─── Provider Kubernetes ─────────────────────────────────────────────────────
provider "kubernetes" {
  host                   = module.azure_infra.kube_host
  client_certificate     = base64decode(module.azure_infra.kube_client_certificate)
  client_key             = base64decode(module.azure_infra.kube_client_key)
  cluster_ca_certificate = base64decode(module.azure_infra.kube_cluster_ca_certificate)
}
