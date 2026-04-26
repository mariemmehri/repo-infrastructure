# configure les providers Terraform azurerm, helm et kubernetes. 
# Il récupère la config du cluster AKS via data.azurerm_kubernetes_cluster
# puis l’utilise pour parler au cluster.


terraform {
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

# Lit la config kube APRES creation du cluster AKS
data "azurerm_kubernetes_cluster" "aks" {
  name                = module.azure_infra.cluster_name
  resource_group_name = var.resource_group_name
  depends_on = [module.azure_infra]
}

# ─── Provider Helm ────────────────────────────────────────────────────────────
# Utilise les outputs INDIVIDUELS du module (plus fiable que kube_config[0])
provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

# ─── Provider Kubernetes ─────────────────────────────────────────────────────
provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}
