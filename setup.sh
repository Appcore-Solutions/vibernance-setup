#!/usr/bin/env bash
# Vibernance setup for Google Cloud (ADR 0013). Run it yourself, as an admin of your own
# organization, in Cloud Shell. It prepares one apps project for Vibernance and gives your
# Vibernance identity the roles it needs there, plus read-only access to whether people in your
# directory are active. It never creates keys. Read README.md for exactly what it changes.
#
#   ./setup.sh --identity <email> --identity-id <number> --project <id>      use an existing project
#   ./setup.sh --identity <email> --identity-id <number> --create-project <id> --billing-account <id>
#   ./setup.sh ... --dry-run             show what would change, change nothing
#   ./setup.sh ... --skip-directory      don't show the owner-left check's Admin console step
#   ./setup.sh --project <id> --identity <email> --identity-id <number> --remove
#                                        take away Vibernance's access; your apps keep running
set -euo pipefail

REGION=us-central1
IDENTITY="" IDENTITY_ID="" PROJECT="" CREATE="" BILLING="" DRY=0 REMOVE=0 SKIP_DIR=0
APPCORE_CUSTOMER_ID=C026oloip
ROLE_NAME="Vibernance directory read"
HERE="$(cd "$(dirname "$0")" && pwd)"

say()  { printf '\n\033[1m%s\033[0m\n' "$*" >&2; }  # stderr, so functions can return values on stdout
fail() { printf '\n\033[31mStopped: %s\033[0m\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --identity) IDENTITY="$2"; shift 2 ;;
    --identity-id) IDENTITY_ID="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --create-project) CREATE="$2"; PROJECT="$2"; shift 2 ;;
    --billing-account) BILLING="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --remove) REMOVE=1; shift ;;
    --skip-directory) SKIP_DIR=1; shift ;;
    *) fail "unknown option $1 (see the top of this file)" ;;
  esac
done

[[ "$IDENTITY" =~ ^cust-[a-z0-9-]+@[a-z0-9-]+\.iam\.gserviceaccount\.com$ ]] || fail "--identity must be your Vibernance identity from the onboarding page (cust-…@….iam.gserviceaccount.com)."
[[ "$IDENTITY_ID" =~ ^[0-9]{10,30}$ ]] || fail "--identity-id must be the number shown next to your Vibernance identity."
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || fail "--project or --create-project must be a Google Cloud project ID."
command -v jq >/dev/null || fail "jq isn't installed (Cloud Shell has it)."
command -v unzip >/dev/null || fail "unzip isn't installed (Cloud Shell has it)."

# OpenTofu, pinned and checksum-verified, in your home directory. A "terraform" that only prints
# install instructions (as Cloud Shell's does now) would otherwise look like success.
TOFU_VERSION=1.13.9
tofu_bin() {
  local dir="$HOME/.vibernance/tofu-$TOFU_VERSION"
  if [ ! -x "$dir/tofu" ]; then
    say "Installing OpenTofu $TOFU_VERSION (open-source Terraform) in $dir"
    local tmp; tmp="$(mktemp -d)"
    local zip="tofu_${TOFU_VERSION}_linux_amd64.zip"
    curl -sSfL -o "$tmp/$zip" "https://github.com/opentofu/opentofu/releases/download/v$TOFU_VERSION/$zip"
    curl -sSfL -o "$tmp/SHA256SUMS" "https://github.com/opentofu/opentofu/releases/download/v$TOFU_VERSION/tofu_${TOFU_VERSION}_SHA256SUMS"
    (cd "$tmp" && grep " $zip\$" SHA256SUMS | sha256sum -c --quiet -) || fail "the OpenTofu download didn't match its checksum."
    mkdir -p "$dir" && unzip -q -o "$tmp/$zip" tofu -d "$dir" && rm -rf "$tmp"
  fi
  "$dir/tofu" version >/dev/null || fail "OpenTofu didn't run."
  echo "$dir/tofu"
}
TOFU="$(tofu_bin)"

ME="$(gcloud config get-value account 2>/dev/null)"
[ -n "$ME" ] || fail "you're not signed in to gcloud."
say "Signed in as $ME"

# --- The project -------------------------------------------------------------------------
if [ -n "$CREATE" ] && ! gcloud projects describe "$PROJECT" >/dev/null 2>&1; then
  [ "$REMOVE" = 0 ] || fail "project $PROJECT doesn't exist, so there's nothing to remove."
  [ -n "$BILLING" ] || fail "--create-project needs --billing-account (find yours with: gcloud billing accounts list)."
  ORG="$(gcloud organizations list --format='value(name)' --limit=1)"
  [ -n "$ORG" ] || fail "you can't see an organization. Sign in as an admin of your organization."
  if [ "$DRY" = 1 ]; then
    say "Dry run. A real run would:"
    echo "  1. Create project $PROJECT in organization $ORG and link billing account $BILLING"
    echo "  2. Create gs://${PROJECT}-vibernance-setup for the setup's record"
    echo "  3. Allow Appcore's customer ID ($APPCORE_CUSTOMER_ID) in domain-restricted sharing on $PROJECT only"
    echo "  4. Turn on Cloud Run, IAP, Artifact Registry and Secret Manager, and create the apps identity and image registry"
    echo "  5. Give $IDENTITY its roles in $PROJECT (see README.md)"
    [ "$SKIP_DIR" = 1 ] || echo "  6. Show you the 2-minute Admin console step for the owner-left check"
    echo
    echo "The detailed plan needs the project to exist. Run without --dry-run to create it; you can re-run --dry-run then."
    exit 0
  fi
  say "Creating project $PROJECT in organization $ORG"
  gcloud projects create "$PROJECT" --organization="$ORG" --name="Vibernance apps" --quiet
  gcloud billing projects link "$PROJECT" --billing-account="$BILLING" --quiet
fi
gcloud projects describe "$PROJECT" >/dev/null 2>&1 || fail "can't read project $PROJECT. Check the ID and that you're an owner."
NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
ORG_ID="$(gcloud projects get-ancestors "$PROJECT" --format=json | jq -r '.[] | select(.type=="organization") | .id')"
[ -n "$ORG_ID" ] || fail "project $PROJECT isn't in an organization. Vibernance needs one (Google Workspace or Cloud Identity)."
CUSTOMER_ID="$(gcloud organizations describe "$ORG_ID" --format='value(owner.directoryCustomerId)')"
DOMAIN="$(gcloud organizations describe "$ORG_ID" --format='value(displayName)')"
say "Project $PROJECT ($NUMBER) in $DOMAIN"

# --- Terraform state, kept in your project so you can re-run or remove later -------------------
BUCKET="${PROJECT}-vibernance-setup"
if ! gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then
  [ "$REMOVE" = 0 ] || fail "there's no setup state in gs://$BUCKET, so this project wasn't set up by this script."
  say "Creating gs://$BUCKET for the setup's state"
  [ "$DRY" = 1 ] || { gcloud services enable storage.googleapis.com --project "$PROJECT" --quiet
                      gcloud storage buckets create "gs://$BUCKET" --project "$PROJECT" --location "$REGION" --uniform-bucket-level-access --quiet
                      gcloud storage buckets update "gs://$BUCKET" --versioning --quiet; }
fi

TF=("$TOFU" -chdir="$HERE/terraform")
TFVARS=(-var "project_id=$PROJECT" -var "region=$REGION" -var "vibernance_service_account=$IDENTITY" -var "vibernance_customer_id=$APPCORE_CUSTOMER_ID")
if [ "$DRY" = 0 ] || gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1; then
  "${TF[@]}" init -input=false -reconfigure -backend-config="bucket=$BUCKET" -backend-config="prefix=vibernance" >/dev/null
fi

# --- Directory role (owner-left check) --------------------------------------------------------
# Google doesn't let a script manage admin roles through gcloud's sign-in, so this one step is
# done in the Admin console. Vibernance's Connection page shows whether it's in place.
directory_steps() {
  say "Last step, in the Google Admin console (about 2 minutes): the owner-left check"
  cat <<EOF
  This lets Vibernance see only whether each person is active, so it can hand an app to its
  sponsor when its owner leaves. Skip it if you'd rather mark people as left in Vibernance.

  1. Open https://admin.google.com/ac/roles and choose Create new role.
  2. Name: $ROLE_NAME
  3. Under "Admin API privileges", tick Users > Read. Nothing else. Create the role.
  4. On the new role, choose Assign service accounts and enter:
       $IDENTITY
EOF
}

if [ "$REMOVE" = 1 ]; then
  say "Removing Vibernance's access to $PROJECT. Your apps, images and logs stay."
  TARGETS=()
  for r in google_project_iam_member.run_admin google_project_iam_member.monitoring_viewer google_project_iam_member.iap_admin \
           google_service_account_iam_member.act_as_apps google_artifact_registry_repository_iam_member.push \
           google_project_iam_member.secret_writer google_project_iam_member.read_requests google_logging_log_view.requests; do
    TARGETS+=(-target="module.vibernance.$r")
  done
  TARGETS+=(-target=google_org_policy_policy.allow_vibernance)
  if [ "$DRY" = 1 ]; then "${TF[@]}" plan -destroy -input=false "${TFVARS[@]}" "${TARGETS[@]}"
  else "${TF[@]}" destroy -input=false -auto-approve "${TFVARS[@]}" "${TARGETS[@]}"; fi
  say "Done. Vibernance can no longer deploy to, read or check anything in $PROJECT."
  echo "If you set up the owner-left check, remove it too: https://admin.google.com/ac/roles > $ROLE_NAME > Delete role."
  echo "Left in place: the apps project, its apps, images, the apps' runtime identity, and gs://$BUCKET (the setup's record)."
  echo "Tell Appcore you've disconnected, so your organization is closed on their side too."
  exit 0
fi

# --- Setup ---------------------------------------------------------------------------------
say "Setting up $PROJECT for Vibernance (about 4 minutes)"
if [ "$DRY" = 1 ]; then "${TF[@]}" plan -input=false "${TFVARS[@]}"; exit 0; fi
"${TF[@]}" apply -input=false -auto-approve "${TFVARS[@]}"
RUNTIME="$("${TF[@]}" output -raw runtime_service_account)"
[[ "$RUNTIME" == vibernance-apps@"$PROJECT".iam.gserviceaccount.com ]] || fail "the setup didn't finish (no apps identity in $PROJECT). Scroll up for the first error, fix it, and run the same command again."

CODE="$(jq -cn --arg p "$PROJECT" --arg n "$NUMBER" --arg r "$REGION" --arg rt "$RUNTIME" --arg c "$CUSTOMER_ID" --arg d "$DOMAIN" --arg i "$IDENTITY" \
  '{v:1, projectId:$p, projectNumber:$n, region:$r, runtimeServiceAccount:$rt, customerId:$c, domain:$d, identity:$i}' | base64 -w0)"
say "Done. Paste this connection code into the Vibernance onboarding page:"
echo "$CODE"
echo
[ "$SKIP_DIR" = 1 ] || directory_steps
echo
echo "To take Vibernance's access away later: ./setup.sh --project $PROJECT --identity $IDENTITY --identity-id $IDENTITY_ID --remove"
