variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}



variable "gke_subnet_prefix" {
  type    = string
  default = "10.0.1.0/24"
}