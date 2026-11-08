# Vibernance setup, run by the customer's admin in their own account (ADR 0013).
# Everything here lives in one project: the apps project Vibernance deploys into.

terraform {
  required_providers {
    google      = { source = "hashicorp/google", version = ">= 6.0" }
    google-beta = { source = "hashicorp/google-beta", version = ">= 6.0" }
    time        = { source = "hashicorp/time", version = ">= 0.11" }
  }
  backend "gcs" {} # bucket and prefix are passed by setup.sh
}

variable "project_id" {
  description = "The apps project Vibernance deploys into."
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "vibernance_service_account" {
  description = "Your organization's Vibernance identity, shown on the onboarding page."
  type        = string
}

variable "vibernance_customer_id" {
  description = "Appcore's Google customer ID, allowed in this project's domain-restricted sharing."
  type        = string
  default     = "C026oloip"
}

variable "allow_vibernance_in_domain_policy" {
  description = "Add the domain-restricted-sharing exception on this project. Only needed if your organization restricts IAM to your own domain (new organizations do by default)."
  type        = bool
  default     = true
}

provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

provider "google-beta" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

resource "google_project_service" "setup" {
  for_each           = toset(["orgpolicy.googleapis.com", "iam.googleapis.com", "logging.googleapis.com"])
  service            = each.value
  disable_on_destroy = false
}

# Let Appcore's accounts hold roles in this project only, merged with your own rule.
resource "google_org_policy_policy" "allow_vibernance" {
  count  = var.allow_vibernance_in_domain_policy ? 1 : 0
  name   = "projects/${var.project_id}/policies/iam.allowedPolicyMemberDomains"
  parent = "projects/${var.project_id}"
  spec {
    inherit_from_parent = true
    rules {
      values {
        allowed_values = [var.vibernance_customer_id]
      }
    }
  }
  depends_on = [google_project_service.setup]
}

# Policy changes take a minute or two to apply; the grants below fail until they do.
resource "time_sleep" "policy_applies" {
  count           = var.allow_vibernance_in_domain_policy ? 1 : 0
  create_duration = "120s"
  depends_on      = [google_org_policy_policy.allow_vibernance]
}

module "vibernance" {
  source                     = "./modules/customer-gcp"
  project_id                 = var.project_id
  region                     = var.region
  vibernance_service_account = var.vibernance_service_account
  depends_on                 = [time_sleep.policy_applies]
}

output "project_number" {
  value = module.vibernance.project_number
}

output "runtime_service_account" {
  value = module.vibernance.runtime_service_account
}
