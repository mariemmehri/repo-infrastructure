output "gke_nodes_sa_email" {
  description = "Email of the GKE nodes service account"
  value       = google_service_account.gke_nodes.email
}

output "gke_nodes_sa_name" {
  description = "Full resource name of the GKE nodes service account"
  value       = google_service_account.gke_nodes.name
}
