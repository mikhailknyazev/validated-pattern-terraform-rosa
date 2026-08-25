#!/bin/bash
# scripts/info/login.sh
# Login to cluster via oc CLI
# Usage: login.sh <cluster-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

PROJECT_ROOT=$(get_project_root)

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

get_cluster_dir "$CLUSTER_NAME" >/dev/null # Validate cluster exists
use_cluster_tf_data_dir "$CLUSTER_NAME"
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)

check_required_tools oc

info "Logging into cluster..."

cd "$TERRAFORM_INFRA_DIR"

EXPECTED_STATE_SUFFIX="clusters/${CLUSTER_NAME}/infrastructure.tfstate"
BACKEND_META="${TF_DATA_DIR}/terraform.tfstate"

# Do not run terraform init — login only needs outputs from this cluster's state.
# Per-cluster TF_DATA_DIR holds backend metadata; verify it targets this cluster.
if [[ ! -f "$BACKEND_META" ]]; then
	error "Terraform is not initialized (missing ${BACKEND_META})."
	error "Initialize for this cluster: make cluster.${CLUSTER_NAME}.init"
	exit 1
fi

BACKEND_REF=$(python3 -c '
import json, sys
try:
    cfg = (json.load(open(sys.argv[1])).get("backend") or {}).get("config") or {}
    # local backend uses path; s3 backend uses key
    print(cfg.get("path") or cfg.get("key") or "")
except Exception:
    print("")
' "$BACKEND_META")

if [[ -z "$BACKEND_REF" ]]; then
	error "Could not determine Terraform backend state location from ${BACKEND_META}."
	error "Re-initialize: make cluster.${CLUSTER_NAME}.init"
	exit 1
fi

case "$BACKEND_REF" in
*"/${EXPECTED_STATE_SUFFIX}" | "${EXPECTED_STATE_SUFFIX}") ;;
*)
	error "Terraform backend is not pointed at this cluster's state."
	error "  expected suffix: ${EXPECTED_STATE_SUFFIX}"
	error "  current:         ${BACKEND_REF}"
	error "Re-initialize: make cluster.${CLUSTER_NAME}.init"
	exit 1
	;;
esac

API_URL=$(terraform output -raw api_url 2>/dev/null || echo "")
if [ -z "$API_URL" ] || [ "$API_URL" = "null" ]; then
	error "Terraform output api_url is missing for cluster '${CLUSTER_NAME}'."
	error "The cluster may not be applied yet. Try: make cluster.${CLUSTER_NAME}.apply"
	exit 1
fi

VPC_CIDR=$(terraform output -raw vpc_cidr_block 2>/dev/null ||
	terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty' || echo "")

if [ -n "$VPC_CIDR" ] && pgrep -f "sshuttle.*$VPC_CIDR" >/dev/null 2>&1; then
	success "sshuttle tunnel active - using direct API URL (traffic routed through bastion)"
fi

# Break-glass admin is opt-in. Gate on terraform outputs — a password override
# cannot help if the HTPasswd admin IDP was never created.
ADMIN_USER_CREATED=$(terraform output -no-color -raw admin_user_created 2>/dev/null | tr -d '\n\r' || echo "false")
# Prefer #28 cluster credentials ARN; fall back to deprecated admin_password_secret_arn alias.
ADMIN_SECRET_ARN=$(terraform output -raw cluster_credentials_secret_arn 2>/dev/null || echo "")
if [ -z "$ADMIN_SECRET_ARN" ] || [ "$ADMIN_SECRET_ARN" = "null" ]; then
	ADMIN_SECRET_ARN=$(terraform output -raw admin_password_secret_arn 2>/dev/null || echo "")
fi

if [ "$ADMIN_USER_CREATED" != "true" ]; then
	EXTERNAL_AUTH=$(terraform output -no-color -raw external_auth_providers_enabled 2>/dev/null || echo "false")
	if [ "$EXTERNAL_AUTH" = "true" ]; then
		error "This cluster uses external authentication providers."
		error "HTPasswd login is not available. Use break-glass credentials instead:"
		error "  make cluster.${CLUSTER_NAME}.break-glass-login"
		exit 1
	fi
	error "No break-glass cluster admin is available (admin_user_created=${ADMIN_USER_CREATED:-false})."
	error "make cluster.${CLUSTER_NAME}.login requires a long-lived HTPasswd admin."
	error "Enable it in clusters/${CLUSTER_NAME}/terraform.tfvars:"
	error "  enable_cluster_admin = true"
	error "Then apply: make cluster.${CLUSTER_NAME}.apply"
	error "GitOps bootstrap uses a short-lived HTPasswd user and does not keep credentials for this login path."
	if [ -n "${TF_VAR_admin_password_override:-}" ]; then
		error "Note: TF_VAR_admin_password_override is set in your environment, but login still needs enable_cluster_admin."
	fi
	exit 1
fi

ADMIN_PASSWORD=""
if [ -n "$ADMIN_SECRET_ARN" ] && [ "$ADMIN_SECRET_ARN" != "null" ]; then
	ADMIN_PASSWORD=$("$PROJECT_ROOT/scripts/utils/get-admin-password.sh" "$TERRAFORM_INFRA_DIR" || echo "")
fi

if [ -z "$ADMIN_PASSWORD" ] && [ -z "${TF_VAR_admin_password_override:-}" ]; then
	error "Break-glass admin exists but no password is available (secret ARN empty and TF_VAR_admin_password_override unset)."
	error "Check AWS Secrets Manager access, or set TF_VAR_admin_password_override."
	exit 1
fi

PASSWORD="${ADMIN_PASSWORD:-${TF_VAR_admin_password_override:-}}"

if oc login "$API_URL" --username admin --password "$PASSWORD" --insecure-skip-tls-verify=false ||
	oc login "$API_URL" --username admin --password "$PASSWORD" --insecure-skip-tls-verify=true; then
	success "Successfully logged into cluster"
else
	error "Login failed. Check credentials and cluster status."
	exit 1
fi

cd - >/dev/null
