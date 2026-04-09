terraform {
   backend "azurerm" {
    resource_group_name  = "ton-resource-group"
    storage_account_name = "tonstorageaccount"
    container_name       = "tfstate"
    key                  = "todo-app.tfstate"
  }
  required_providers {
    #    azurerm    → plugin qui parle à l'API Azure
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

# Ces providers ont besoin du cluster AKS pour s'authentifier
# Ils dépendent donc du module azure-infra
provider "helm" {
  kubernetes {
    host                   = module.azure_infra.kube_config.host
    client_certificate     = base64decode(module.azure_infra.kube_config.client_certificate)
    client_key             = base64decode(module.azure_infra.kube_config.client_key)
    cluster_ca_certificate = base64decode(module.azure_infra.kube_config.cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = module.azure_infra.kube_config.host
  client_certificate     = base64decode(module.azure_infra.kube_config.client_certificate)
  client_key             = base64decode(module.azure_infra.kube_config.client_key)
  cluster_ca_certificate = base64decode(module.azure_infra.kube_config.cluster_ca_certificate)
}