variable "resource_group_name" {
  description = "Resource group contenant le cluster AKS"
  type        = string
}

variable "cluster_name" {
  description = "Nom du cluster AKS deja provisionne"
  type        = string
}

variable "config_repo_url" {
  description = "URL Git du repo de configuration GitOps"
  type        = string
  default     = "https://github.com/mariemmehri/repo-config"
}

variable "config_repo_revision" {
  description = "Branche/tag Git a suivre par ArgoCD"
  type        = string
  default     = "main"
}

variable "child_apps_path" {
  description = "Dossier des applications enfants dans le config repo"
  type        = string
  default     = "apps/children"
}
