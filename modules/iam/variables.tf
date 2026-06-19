variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "terraform_ci_sa_email" {
  description = "Email of the Terraform CI service account (sa-terraform-ci)"
  type        = string
}

variable "developer_group_email" {
  description = "Google group email for developer kubectl read access. Set for staging, null for prod."
  type        = string
  default     = null
}
