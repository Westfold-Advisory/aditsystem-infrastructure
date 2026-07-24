#!/usr/bin/env bash
# setup-github.sh — run once after `terraform apply` in bootstrap/
#
# What it does:
#   1. Reads Terraform outputs from bootstrap/
#   2. Creates config/backend-dev.hcl and config/backend-prod.hcl
#   3. Sets GitHub Actions secrets and variables via the gh CLI
#   4. Prints a checklist of manual steps (GitHub Environments)
#
# Prerequisites:
#   - terraform applied successfully in bootstrap/  (state in .terraform/*)
#   - gh CLI installed and logged in (gh auth status)
#   - jq installed (brew install jq  /  apt install jq)
#
# Usage:
#   cd <repo-root>
#   bash scripts/setup-github.sh

set -euo pipefail

REPO="ervicperezdev/aditsystem-infrastructure"
BOOTSTRAP_DIR="$(cd "$(dirname "$0")/../bootstrap" && pwd)"
CONFIG_DIR="$(cd "$(dirname "$0")/../config" && pwd)"

echo "==> Reading Terraform outputs from bootstrap..."
cd "$BOOTSTRAP_DIR"

STATE_BUCKET=$(terraform output -raw state_bucket)
DYNAMO_TABLE=$(terraform output -raw dynamodb_table)
ROLE_ARN=$(terraform output -raw github_actions_role_arn)
AWS_REGION=$(terraform output -json | jq -r '.backend_config_dev.value | capture("region\\s+=\\s+\"(?P<r>[^\"]+)\"") | .r')

echo "    state_bucket  : $STATE_BUCKET"
echo "    dynamodb_table: $DYNAMO_TABLE"
echo "    role_arn      : $ROLE_ARN"
echo "    aws_region    : $AWS_REGION"

# ── 1. Backend config files ───────────────────────────────────────────────────

echo ""
echo "==> Writing config/backend-dev.hcl ..."
cat > "$CONFIG_DIR/backend-dev.hcl" <<HCL
bucket         = "$STATE_BUCKET"
key            = "dev/terraform.tfstate"
region         = "$AWS_REGION"
dynamodb_table = "$DYNAMO_TABLE"
encrypt        = true
HCL

echo "==> Writing config/backend-prod.hcl ..."
cat > "$CONFIG_DIR/backend-prod.hcl" <<HCL
bucket         = "$STATE_BUCKET"
key            = "prod/terraform.tfstate"
region         = "$AWS_REGION"
dynamodb_table = "$DYNAMO_TABLE"
encrypt        = true
HCL

echo "    Done. These files are git-ignored — do not commit them."

# ── 2. GitHub Secrets ─────────────────────────────────────────────────────────

echo ""
echo "==> Setting GitHub Actions secrets on $REPO ..."
gh secret set AWS_ROLE_ARN        --repo "$REPO" --body "$ROLE_ARN"
echo "    AWS_ROLE_ARN set."

# INFRACOST_API_KEY must be provided manually — we never have it here
echo ""
echo "    INFRACOST_API_KEY: set it manually —"
echo "      gh secret set INFRACOST_API_KEY --repo $REPO"
echo "    Get a free key at https://www.infracost.io/docs/"

# ── 3. GitHub Variables ───────────────────────────────────────────────────────

echo ""
echo "==> Setting GitHub Actions variables on $REPO ..."
gh variable set AWS_REGION              --repo "$REPO" --body "$AWS_REGION"
gh variable set TF_STATE_BUCKET         --repo "$REPO" --body "$STATE_BUCKET"
gh variable set TF_STATE_LOCK_TABLE     --repo "$REPO" --body "$DYNAMO_TABLE"
gh variable set TF_REMOTE_STATE_ENABLED --repo "$REPO" --body "false"   # enable after first manual plan succeeds
gh variable set INFRACOST_ENABLED       --repo "$REPO" --body "false"   # enable after INFRACOST_API_KEY is set
echo "    Variables set. TF_REMOTE_STATE_ENABLED and INFRACOST_ENABLED start as 'false'."
echo "    Flip them to 'true' once you have verified the pipeline works end-to-end."

# ── 4. Manual steps reminder ──────────────────────────────────────────────────

echo ""
echo "================================================================"
echo " MANUAL STEPS REMAINING (GitHub UI)"
echo "================================================================"
echo ""
echo " 1. Create GitHub Environments:"
echo "    https://github.com/$REPO/settings/environments"
echo ""
echo "    a) 'development'  — no restrictions"
echo "    b) 'production'   — enable Required reviewers, restrict to branch 'main'"
echo ""
echo " 2. Set INFRACOST_API_KEY secret (see above)"
echo ""
echo " 3. When ready to enable remote state:"
echo "    gh variable set TF_REMOTE_STATE_ENABLED --repo $REPO --body true"
echo ""
echo " 4. When Infracost API key is set:"
echo "    gh variable set INFRACOST_ENABLED --repo $REPO --body true"
echo ""
echo "================================================================"
echo " DONE"
echo "================================================================"
