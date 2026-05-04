output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "registry_login_server" {
  value = module.artifact_registry.acr_login_server
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