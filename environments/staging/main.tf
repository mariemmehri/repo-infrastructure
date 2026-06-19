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

module "iam" {
  source                = "../../modules/iam"
  project_id            = var.project_id
  environment           = "staging"
  terraform_ci_sa_email = "sa-terraform-ci@${var.project_id}.iam.gserviceaccount.com"
  developer_group_email = var.developer_group_email
}

module "gke" {
  source              = "../../modules/gke"
  cluster_name        = var.cluster_name
  project_id          = var.project_id
  region              = var.region
  environment         = "staging"
  node_count          = var.node_count
  node_vm_size        = var.node_vm_size
  disk_size_gb        = var.disk_size_gb
  release_channel     = var.release_channel
  vpc_name            = module.networking.vpc_name
  gke_subnet_id       = module.networking.gke_subnet_id
  gke_nodes_sa_email  = module.iam.gke_nodes_sa_email
  depends_on          = [module.networking, module.iam]
}
