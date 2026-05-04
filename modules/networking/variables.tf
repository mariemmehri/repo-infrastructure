variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "vnet_address_space" {
  description = "Non utilisé sur GCP (le CIDR est sur le subnet)"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "gke_subnet_prefix" {
  type    = string
  default = "10.0.1.0/24"
}