#!/bin/bash
# scripts/cluster/apply-infrastructure.sh
# Apply infrastructure changes
# Usage: apply-infrastructure.sh <cluster-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

CLUSTER_DIR=$(get_cluster_dir "$CLUSTER_NAME")
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)

# Plan file is in cluster directory
PLAN_FILE="$CLUSTER_DIR/terraform.tfplan"

# Ensure plan exists
if [ ! -f "$PLAN_FILE" ]; then
	info "Plan not found, planning first..."
	"$SCRIPT_DIR/plan-infrastructure.sh" "$CLUSTER_NAME"
fi

info "Applying infrastructure changes..."

cd "$TERRAFORM_INFRA_DIR"

# Use relative path from terraform directory to cluster directory
terraform apply "../clusters/$CLUSTER_NAME/terraform.tfplan"

success "Infrastructure applied successfully"
