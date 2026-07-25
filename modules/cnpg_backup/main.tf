terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# WAL/base backup destination for CNPG's barman-cloud CNPG-I plugin.
# Versioning stays off — Barman manages its own retention; a GCS lifecycle
# rule here would fight Barman's own pruning instead of complementing it.
resource "google_storage_bucket" "cnpg_backup" {
  name          = var.backup_bucket_name
  location      = var.region
  project       = var.project_id
  force_destroy = false

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    purpose     = "cnpg-postgres-backups"
    environment = var.environment
    managed-by  = "terraform"
    project     = "pfe"
  }
}

# Dedicated, narrowly-scoped SA — deliberately not sa-gke-<env>-pfe (the node
# SA), same "one SA per purpose" pattern modules/iam already follows.
resource "google_service_account" "cnpg_backup" {
  account_id   = "sa-cnpg-${var.environment}-backup"
  display_name = "CNPG barman-cloud backup SA - ${var.environment}"
  project      = var.project_id
}

# Scoped to this bucket only — not roles/storage.admin at project level.
resource "google_storage_bucket_iam_member" "cnpg_backup_writer" {
  bucket = google_storage_bucket.cnpg_backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cnpg_backup.email}"
}

# roles/storage.objectAdmin alone does NOT include storage.buckets.get —
# barman-cloud's preflight check ("barman-cloud-check-wal-archive") calls the
# bucket metadata GET before archiving/backing up, and fails every backup
# with a 403 without this. Still scoped to this bucket only, not
# roles/storage.admin (which would also grant bucket delete / IAM changes).
resource "google_storage_bucket_iam_member" "cnpg_backup_bucket_reader" {
  bucket = google_storage_bucket.cnpg_backup.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.cnpg_backup.email}"
}

# GKE Workload Identity binding: lets the Kubernetes ServiceAccount
# (annotated iam.gke.io/gcp-service-account in repo-config) impersonate
# this GSA — no downloaded JSON key involved.
resource "google_service_account_iam_member" "cnpg_backup_workload_identity" {
  service_account_id = google_service_account.cnpg_backup.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.ksa_namespace}/${var.ksa_name}]"
}
