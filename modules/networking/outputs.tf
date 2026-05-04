output "vpc_id" {
  value = google_compute_network.main.id
}

output "gke_subnet_id" {
  value = google_compute_subnetwork.aks.id
}

output "vpc_name" {
  value = google_compute_network.main.name
}