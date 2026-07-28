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

# Registre isolé pour la prod — seules les images promues par tag (promote-prod.yml)
# y sont copiées; le CI develop/main ne pousse jamais ici.
module "artifact_registry_prod" {
  source      = "../../modules/artifact_registry"
  acr_name    = var.prod_registry_name
  project_id  = var.project_id
  region      = var.region
  environment = "prod"
}

module "iam" {
  source                = "../../modules/iam"
  project_id            = var.project_id
  environment           = "staging"
  terraform_ci_sa_email = "sa-terraform-ci@${var.project_id}.iam.gserviceaccount.com"
  developer_group_email = var.developer_group_email
}

module "gke" {
  source             = "../../modules/gke"
  cluster_name       = var.cluster_name
  project_id         = var.project_id
  region             = var.region
  environment        = "staging"
  node_count         = var.node_count
  max_node_count     = var.max_node_count
  node_vm_size       = var.node_vm_size
  disk_size_gb       = var.disk_size_gb
  release_channel    = var.release_channel
  vpc_name           = module.networking.vpc_name
  gke_subnet_id      = module.networking.gke_subnet_id
  gke_nodes_sa_email = module.iam.gke_nodes_sa_email
  depends_on         = [module.networking, module.iam]
}

# Backup destination for CNPG's barman-cloud CNPG-I plugin — additive only,
# no other module depends on it. See repo-config for the operator/Cluster/
# plugin wiring that actually consumes this bucket + GSA.
module "cnpg_backup" {
  source             = "../../modules/cnpg_backup"
  project_id         = var.project_id
  environment        = "staging"
  region             = var.region
  backup_bucket_name = var.cnpg_backup_bucket_name
  ksa_namespace      = var.cnpg_ksa_namespace
  ksa_name           = var.cnpg_ksa_name
}

# Same module, one instantiation per environment — mirrors the
# artifact_registry / artifact_registry_prod pattern above. Each env gets its
# own bucket + dedicated GSA + WIF binding scoped to its own namespace/KSA.
module "cnpg_backup_dev" {
  source             = "../../modules/cnpg_backup"
  project_id         = var.project_id
  environment        = "dev"
  region             = var.region
  backup_bucket_name = var.cnpg_backup_bucket_name_dev
  ksa_namespace      = "dev"
  ksa_name           = "pg-dev"
}

module "cnpg_backup_prod" {
  source             = "../../modules/cnpg_backup"
  project_id         = var.project_id
  environment        = "prod"
  region             = var.region
  backup_bucket_name = var.cnpg_backup_bucket_name_prod
  ksa_namespace      = "prod"
  ksa_name           = "pg-prod"
}
