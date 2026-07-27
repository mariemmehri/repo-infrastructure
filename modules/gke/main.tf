
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

data "google_client_config" "default" {}


# Cluster GKE — on désactive le node pool par défaut
# pour le gérer séparément (bonne pratique)
resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = "${var.region}-b"
  project  = var.project_id

  network    = var.vpc_name
  subnetwork = var.gke_subnet_id

  # Supprime le node pool default imposé par GCP
  # On crée le nôtre juste en dessous
  remove_default_node_pool    = true
  initial_node_count          = 1
  enable_intranode_visibility = true


  node_config {
    spot = true
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  deletion_protection = false
  networking_mode     = "VPC_NATIVE"
  ip_allocation_policy {}

  release_channel {
    channel = upper(var.release_channel)
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # CKV_GCP_13 — disable client certificate auth; rely on OIDC/WIF instead
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # CKV_GCP_65 — enforce Kubernetes NetworkPolicy via Calico
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # CKV_GCP_66 — enforce project-level Binary Authorization policy
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # CKV_GCP_25 — restrict which CIDRs can reach the Kubernetes API
  # 0.0.0.0/0 required for GitHub Actions (dynamic IPs); tighten post-PFE
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "allow-all"
    }
  }

  resource_labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
}

# Node pool séparé 
resource "google_container_node_pool" "default" {
  name           = "default"
  cluster        = google_container_cluster.gke.id
  location       = "${var.region}-b"
  node_locations = ["${var.region}-b"]
  project        = var.project_id

  autoscaling {
    min_node_count = var.node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_upgrade = true
    auto_repair  = true
  }

  node_config {
    machine_type    = var.node_vm_size
    disk_size_gb    = var.disk_size_gb
    service_account = var.gke_nodes_sa_email
    spot            = true


    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }

    # CKV_GCP_68/69/70 — shielded nodes: secure boot + integrity monitoring
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # CKV_GCP_70 — use GKE metadata server to protect node metadata from pods
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

}