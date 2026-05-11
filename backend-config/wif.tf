# ============================================================
# Workload Identity Federation
# Permet à GitHub Actions de s'authentifier sur GCP sans clé JSON
# ============================================================

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

data "google_project" "current" {
  project_id = var.project_id
}

# ─── Workload Identity Pool ────────────────────────────────
resource "google_iam_workload_identity_pool" "github" {
  project                   = data.google_project.current.number
  workload_identity_pool_id = "github-pool-v2"
  display_name              = "GitHub Actions Pool"
  description               = "Pool pour GitHub Actions CI/CD - PFE"

  depends_on = [google_project_service.iam_credentials]
}

# ─── Provider OIDC GitHub ──────────────────────────────────
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

  # Sécurité : restreindre aux repos de ton organisation uniquement
  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ─── Service Account Terraform CI ──────────────────────────
resource "google_service_account" "terraform_ci" {
  project      = var.project_id
  account_id   = "sa-terraform-ci"
  display_name = "Terraform CI - GitHub Actions"
  description  = "Service account utilisé par le pipeline Terraform CI"
}

# ─── Permissions IAM sur le projet ─────────────────────────
locals {
  terraform_ci_roles = [
    "roles/container.admin",
    "roles/compute.networkAdmin",
    "roles/artifactregistry.admin",
    "roles/storage.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
  ]
}

resource "google_project_iam_member" "terraform_ci" {
  for_each = toset(local.terraform_ci_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.terraform_ci.email}"
}

# ─── Liaison GitHub repo infra → Service Account ───────────
resource "google_service_account_iam_member" "github_wif_infra" {
  service_account_id = google_service_account.terraform_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_infra_repo}"
}

# ─── Liaison GitHub repo app → Service Account ─────────────
# Nécessaire pour le pipeline CI application (docker build push)
resource "google_service_account_iam_member" "github_wif_app" {
  service_account_id = google_service_account.terraform_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.github_app_repo}"
}