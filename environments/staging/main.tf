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
  depends_on    = [module.networking]
}
# Module 4 — Installe ArgoCD dans le cluster GKE
module "argocd" {
  source               = "../../modules/argocd"
  argocd_chart_version = var.argocd_chart_version
  depends_on           = [module.gke]
  # kube_host                   = module.gke.kube_host
  # kube_client_certificate     = module.gke.kube_client_certificate
  # kube_client_key             = module.gke.kube_client_key
  # kube_cluster_ca_certificate = module.gke.kube_cluster_ca_certificate
}
# ─── Nouveau — binding terraform-ci peut utiliser le SA GKE ─
resource "google_service_account_iam_member" "terraform_ci_uses_gke_sa" {
  service_account_id = module.gke.gke_nodes_sa_name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:sa-terraform-ci@${var.project_id}.iam.gserviceaccount.com"
  depends_on         = [module.gke]
}
