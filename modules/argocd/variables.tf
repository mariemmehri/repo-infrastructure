variable "kube_host" {
  type      = string
  sensitive = true
}

variable "kube_client_certificate" {
  type      = string
  sensitive = true
}

variable "kube_client_key" {
  type      = string
  sensitive = true
}

variable "kube_cluster_ca_certificate" {
  type      = string
  sensitive = true
}

variable "argocd_chart_version" {
  type    = string
  default = "6.7.3"
}