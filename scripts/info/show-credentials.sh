#!/bin/bash
# scripts/info/show-credentials.sh
# Show admin credentials
# Usage: show-credentials.sh <cluster-name>

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

CLUSTER_DIR=$(get_cluster_dir "$CLUSTER_NAME")
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)

# Get network config
source "$PROJECT_ROOT/scripts/utils/get-network-config.sh" "$CLUSTER_DIR"

info "$CLUSTER_NAME Cluster Credentials ($MODE):"

# Get admin password
ADMIN_PASSWORD=$("$PROJECT_ROOT/scripts/utils/get-admin-password.sh" "$TERRAFORM_INFRA_DIR" 2>/dev/null || echo "")

if [ -n "$ADMIN_PASSWORD" ]; then
	echo "Admin Username: admin"
	echo "Admin Password: $ADMIN_PASSWORD"
elif [ -n "${TF_VAR_admin_password_override:-}" ]; then
	echo "Admin Username: admin"
	echo "Admin Password: $TF_VAR_admin_password_override"
else
	warn "Admin password not available."
	warn "Infrastructure may not be deployed or secret not found."
	warn "Set TF_VAR_admin_password_override to provide password manually."
fi
