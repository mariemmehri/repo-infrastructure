output "argocd_app_name" {
  value = "app-of-apps"
}

output "argocd_sync_command" {
  value = "argocd app sync app-of-apps"
}