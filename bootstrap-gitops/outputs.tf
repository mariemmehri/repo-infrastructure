output "argocd_app_name" {
  value = "root-app"
}

output "argocd_sync_command" {
  value = "argocd app sync root-app"
}