output "cluster_name" {
  value = google_container_cluster.gke.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.gke.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.gke.master_auth[0].cluster_ca_certificate
  sensitive = true
}

# Ces outputs sont gardés avec les mêmes noms
# pour ne pas casser les providers helm/kubernetes
output "kube_host" {
  value     = "https://${google_container_cluster.gke.endpoint}"
  sensitive = true
}

output "kube_client_certificate" {
  value     = google_container_cluster.gke.master_auth[0].client_certificate
  sensitive = true
}
output "kube_token" {
  value     = data.google_client_config.default.access_token
  sensitive = true
}

output "kube_client_key" {
  value     = google_container_cluster.gke.master_auth[0].client_key
  sensitive = true
}

output "kube_cluster_ca_certificate" {
  value     = google_container_cluster.gke.master_auth[0].cluster_ca_certificate
  sensitive = true
}
# ─── Nouveaux ───────────────────────────────────────────────
output "gke_nodes_sa_email" {
  description = "Email du Service Account des nodes GKE"
  value       = google_service_account.gke_nodes.email
}

output "gke_nodes_sa_name" {
  description = "Nom complet du Service Account des nodes GKE"
  value       = google_service_account.gke_nodes.name
}