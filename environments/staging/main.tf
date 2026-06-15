module "networking" {
  source      = "../../modules/networking"
  project_id  = var.project_id
  region      = var.region
  environment = "staging"
}

module "artifact_registry" {
  source      = "../../modules/artifact_registry"
  acr_name    = var.registry_name
  project_id  = var.project_id
  region      = var.region
  environment = "staging"
}

module "gke" {
  source        = "../../modules/gke"
  cluster_name  = var.cluster_name
  project_id    = var.project_id
  region        = var.region
  environment   = "staging"
  node_count    = var.node_count
  node_vm_size  = var.node_vm_size
  vpc_name      = module.networking.vpc_name
  gke_subnet_id = module.networking.gke_subnet_id
  depends_on    = [module.networking]
}

resource "google_service_account_iam_member" "terraform_ci_uses_gke_sa" {
  service_account_id = module.gke.gke_nodes_sa_name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:sa-terraform-ci@${var.project_id}.iam.gserviceaccount.com"
  depends_on         = [module.gke]
}
