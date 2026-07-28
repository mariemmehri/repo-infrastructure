output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "registry_login_server" {
  value = module.artifact_registry.acr_login_server
}

output "prod_registry_login_server" {
  value = module.artifact_registry_prod.acr_login_server
}

output "kubectl_command" {
  value = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id}"
}

output "argocd_portforward" {
  value = "kubectl port-forward svc/argocd-server -n argocd 9089:80"
}

output "argocd_password" {
  value = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
}

output "cnpg_backup_bucket_name" {
  value = module.cnpg_backup.backup_bucket_name
}

output "cnpg_backup_sa_email" {
  value = module.cnpg_backup.cnpg_backup_sa_email
}

output "cnpg_backup_bucket_name_dev" {
  value = module.cnpg_backup_dev.backup_bucket_name
}

output "cnpg_backup_sa_email_dev" {
  value = module.cnpg_backup_dev.cnpg_backup_sa_email
}

output "cnpg_backup_bucket_name_prod" {
  value = module.cnpg_backup_prod.backup_bucket_name
}

output "cnpg_backup_sa_email_prod" {
  value = module.cnpg_backup_prod.cnpg_backup_sa_email
}