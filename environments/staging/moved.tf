moved {
  from = module.gke.google_service_account.gke_nodes
  to   = module.iam.google_service_account.gke_nodes
}

moved {
  from = module.gke.google_project_iam_member.artifact_registry_reader
  to   = module.iam.google_project_iam_member.gke_node_roles["roles/artifactregistry.reader"]
}

moved {
  from = google_service_account_iam_member.terraform_ci_uses_gke_sa
  to   = module.iam.google_service_account_iam_member.terraform_ci_uses_gke_sa
}
