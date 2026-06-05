# ============================================================
# Workload Identity Federation
# Permet à GitHub Actions de s'authentifier sur GCP sans clé JSON
#
# ARCHITECTURE:
# sa-terraform-ci    → repo infra (Terraform apply)
# sa-github-actions  → repo app   (docker build/push)
# ============================================================

# ─── APIs requises ─────────────────────────────────────────
resource "google_project_service" "iam_credentials" {
  project            = var.project_id
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sts" {
  project            = var.project_id
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# ─── Données projet ────────────────────────────────────────
data "google_project" "current" {
  project_id = var.project_id
}

# ═══════════════════════════════════════════════════════════
# WORKLOAD IDENTITY POOL & PROVIDER
# ═══════════════════════════════════════════════════════════
# This creates the "identity provider" in GCP
# Think of it as GCP saying:
# "I will trust tokens from this specific source"
resource "google_iam_workload_identity_pool" "github" {
  project                   = data.google_project.current.number
  workload_identity_pool_id = "github-pool-v2"
  display_name              = "GitHub Actions Pool"
  description               = "Pool pour GitHub Actions CI/CD - PFE"
  depends_on                = [google_project_service.iam_credentials]
}


resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = data.google_project.current.number
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub" 
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ═══════════════════════════════════════════════════════════
# SERVICE ACCOUNT 1 — TERRAFORM CI (repo infra)
# ═══════════════════════════════════════════════════════════

resource "google_service_account" "terraform_ci" {
  project      = var.project_id
  account_id   = "sa-terraform-ci"
  display_name = "Terraform CI - GitHub Actions"
  description  = "Service account pour le pipeline Terraform (infra)"
}

# Rôles Terraform CI
locals {
  terraform_ci_roles = [
    "roles/container.admin",
    "roles/compute.networkAdmin",
    "roles/artifactregistry.admin",
    "roles/storage.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
  ]
}

resource "google_project_iam_member" "terraform_ci" {
  for_each = toset(local.terraform_ci_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.terraform_ci.email}"
}

# WIF binding — repo infrastructure uniquement
resource "google_service_account_iam_member" "github_wif_infra" {
  service_account_id = google_service_account.terraform_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_infra_repo}"
}

# ═══════════════════════════════════════════════════════════
# SERVICE ACCOUNT 2 — GITHUB ACTIONS CI (repo application)
# ═══════════════════════════════════════════════════════════

resource "google_service_account" "github_actions_ci" {
  project      = var.project_id
  account_id   = "sa-github-actions"
  display_name = "GitHub Actions CI/CD"
  description  = "Service account pour le pipeline CI application (docker build/push)"
}

# Rôles CI application
locals {
  github_actions_roles = [
    "roles/artifactregistry.writer", # docker push
    "roles/container.developer",     # kubectl (optionnel)
    "roles/storage.objectViewer",    # lire GCS si besoin
  ]
}

resource "google_project_iam_member" "github_actions_ci" {
  for_each = toset(local.github_actions_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.github_actions_ci.email}"
}

# WIF binding — repo application uniquement
resource "google_service_account_iam_member" "github_wif_app" {
  service_account_id = google_service_account.github_actions_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_app_repo}"
}

