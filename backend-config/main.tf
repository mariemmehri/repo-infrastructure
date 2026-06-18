terraform {
  # Backend LOCAL intentionnellement
  # même logique poulet/oeuf qu'Azure
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_storage_bucket" "tfstate_logs" {
  name          = "${var.bucket_name}-logs"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    purpose    = "terraform-state-access-logs"
    managed-by = "terraform"
    project    = "pfe"
  }
}

resource "google_storage_bucket" "tfstate" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 7
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  logging {
    log_bucket        = google_storage_bucket.tfstate_logs.name
    log_object_prefix = "tfstate-access/"
  }

  labels = {
    purpose    = "terraform-remote-backend"
    managed-by = "terraform"
    project    = "pfe"
  }
}