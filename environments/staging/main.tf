#appele aux modules pour créer les ressources
# Module 1 — Crée le réseau
module "networking" {
  source      = "../../modules/networking"
  project_id  = var.project_id
  region      = var.region
  environment = "staging"
}

# Module 2 — Crée le registre d'artifacts 
module "artifact_registry" {
  source      = "../../modules/artifact_registry"
  acr_name    = var.registry_name
  project_id  = var.project_id
  region      = var.region
  environment = "staging"
}

# Module 3 — Crée le cluster GKE
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
  depends_on = [module.networking]
}
# Module 4 — Installe ArgoCD dans le cluster GKE
module "argocd" {
  source                      = "../../modules/argocd"
  kube_host                   = module.gke.kube_host
  kube_client_certificate     = module.gke.kube_client_certificate
  kube_client_key             = module.gke.kube_client_key
  kube_cluster_ca_certificate = module.gke.kube_cluster_ca_certificate

  depends_on = [module.gke]
}