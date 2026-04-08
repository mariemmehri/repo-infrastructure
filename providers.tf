terraform {
  required_providers {
    #    azurerm    → plugin qui parle à l'API Azure
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}
