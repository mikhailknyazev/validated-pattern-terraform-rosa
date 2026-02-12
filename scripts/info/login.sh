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
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)

check_required_tools oc

info "Logging into cluster..."

cd "$TERRAFORM_INFRA_DIR"

API_URL=$(terraform output -raw api_url 2>/dev/null || echo "")
if [ -z "$API_URL" ]; then
	error "Cluster not deployed or api_url output not available"
	exit 1
fi

VPC_CIDR=$(terraform output -raw vpc_cidr_block 2>/dev/null ||
	terraform output -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty' || echo "")

if [ -n "$VPC_CIDR" ] && pgrep -f "sshuttle.*$VPC_CIDR" >/dev/null 2>&1; then
	success "sshuttle tunnel active - using direct API URL (traffic routed through bastion)"
fi

# Get admin password
ADMIN_PASSWORD=$("$PROJECT_ROOT/scripts/utils/get-admin-password.sh" "$TERRAFORM_INFRA_DIR" || echo "")

if [ -z "$ADMIN_PASSWORD" ] && [ -z "${TF_VAR_admin_password_override:-}" ]; then
	error "Admin password not found and TF_VAR_admin_password_override not set."
	error "You may need to:"
	error "  1. Re-apply infrastructure: $PROJECT_ROOT/scripts/cluster/apply-infrastructure.sh $CLUSTER_NAME"
	error "  2. Or set TF_VAR_admin_password_override environment variable"
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
