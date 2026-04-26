variable "location" {
  description = "Azure region"
  type        = string
  default     = "swedencentral"
}

variable "resource_group_name" {
  description = "Resource group for tfstate storage"
  type        = string
  default     = "rg-tfstate-pfe"
}

variable "storage_account_name" {
  description = "Storage account name (globally unique, lowercase, no hyphens)"
  type        = string
}

variable "container_name" {
  description = "Blob container name"
  type        = string
  default     = "tfstate"
}
