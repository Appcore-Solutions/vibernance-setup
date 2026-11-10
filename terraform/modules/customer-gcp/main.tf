# The one-time setup a Google Cloud customer runs (ADR 0008, point 6).
# It prepares one dedicated project for Vibernance-managed apps and lets exactly one
# identity, the customer's Vibernance service account, deploy into it (ADR 0004).
# Nothing here creates keys. The customer removes Vibernance's access by deleting the
# IAM bindings below.

terraform {
  required_providers {
    google      = { source = "hashicorp/google" }
    google-beta = { source = "hashicorp/google-beta" }
    time        = { source = "hashicorp/time" }
  }
}

variable "project_id" {
  description = "The customer's project for Vibernance-managed apps."
  type        = string
}

variable "region" {
  type = string
}

variable "vibernance_service_account" {
  description = "Email of the customer's Vibernance identity, given by Appcore."
  type        = string
}

locals {
  services   = ["run.googleapis.com", "iap.googleapis.com", "artifactregistry.googleapis.com", "secretmanager.googleapis.com"]
  vibernance = "serviceAccount:${var.vibernance_service_account}"
}

resource "google_project_service" "this" {
  for_each           = toset(local.services)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# On a new project, Google can refuse calls to a just-enabled API for a minute or two
# ("SERVICE_DISABLED", seen creating the image repository). Wait once; re-runs don't wait again.
resource "time_sleep" "apis_ready" {
  create_duration = "90s"
  depends_on      = [google_project_service.this]
}

data "google_project" "this" {
  project_id = var.project_id
}

# IAP's service agent must exist before apps can be put behind sign-in.
resource "google_project_service_identity" "iap" {
  provider   = google-beta
  project    = var.project_id
  service    = "iap.googleapis.com"
  depends_on = [time_sleep.apis_ready]
}

# Identity the deployed apps run as. It has no roles; apps get only what they're given.
resource "google_service_account" "apps" {
  project      = var.project_id
  account_id   = "vibernance-apps"
  display_name = "Runtime identity for Vibernance-managed apps"
}

resource "google_artifact_registry_repository" "apps" {
  project       = var.project_id
  location      = var.region
  repository_id = "vibernance-apps"
  format        = "DOCKER"
  description   = "Images of apps that passed the Vibernance security gate"
  depends_on    = [time_sleep.apis_ready]
}

# --- What Vibernance may do in this project ----------------------------------------
# Deploy and manage Cloud Run services, including their invoker policy.
resource "google_project_iam_member" "run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = local.vibernance
}

# Read the apps' Cloud Run metrics (M6): request and error counts for the hourly health check
# and daily activity. Read-only. No logs, no identities, no app data.
resource "google_project_iam_member" "monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = local.vibernance
}

# Turn on sign-in for each app and set who may pass it.
resource "google_project_iam_member" "iap_admin" {
  project = var.project_id
  role    = "roles/iap.admin"
  member  = local.vibernance
}

# Run apps as the runtime identity above, and only that one.
resource "google_service_account_iam_member" "act_as_apps" {
  service_account_id = google_service_account.apps.name
  role               = "roles/iam.serviceAccountUser"
  member             = local.vibernance
}

# Push gated images.
resource "google_artifact_registry_repository_iam_member" "push" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.apps.repository_id
  role       = "roles/artifactregistry.writer"
  member     = local.vibernance
}

# App secrets (ADR 0007): Vibernance can create secrets and add values, but can't read them
# and can't change who may read them. Only the apps' runtime identity reads them, and only
# secrets Vibernance manages (named vb-*).
resource "google_project_iam_custom_role" "secret_writer" {
  project     = var.project_id
  role_id     = "vibernanceSecretWriter"
  title       = "Vibernance secret writer"
  description = "Create secrets and add versions. No access to values, no IAM changes."
  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.get",
    "secretmanager.versions.add",
  ]
}

resource "google_project_iam_member" "secret_writer" {
  project = var.project_id
  role    = google_project_iam_custom_role.secret_writer.id
  member  = local.vibernance
}

resource "google_project_iam_member" "apps_read_vibernance_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = google_service_account.apps.member
  condition {
    title      = "vibernance-managed-secrets"
    expression = "resource.name.startsWith(\"projects/${data.google_project.this.number}/secrets/vb-\")"
  }
}

# --- Activity (M6) ----------------------------------------------------------------------
# Visitors and requests per app, counted from the request logs Cloud Run already writes. Nothing
# is switched on here. Vibernance reads only through this view of request logs; IP addresses and
# browsers are counted in the worker and never leave the project, only daily counts do.
resource "google_logging_log_view" "requests" {
  name        = "vibernance-requests"
  bucket      = "projects/${var.project_id}/locations/global/buckets/_Default"
  description = "Cloud Run request logs, for Vibernance's daily visitor counts"
  filter      = "LOG_ID(\"run.googleapis.com/requests\")"
}

resource "google_project_iam_member" "read_requests" {
  project = var.project_id
  role    = "roles/logging.viewAccessor"
  member  = local.vibernance
  condition {
    title      = "vibernance-requests-view"
    expression = "resource.name == \"${google_logging_log_view.requests.id}\""
  }
}

output "project_number" {
  value = data.google_project.this.number
}

output "runtime_service_account" {
  value = google_service_account.apps.email
}

output "image_repository" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.apps.repository_id}"
}
