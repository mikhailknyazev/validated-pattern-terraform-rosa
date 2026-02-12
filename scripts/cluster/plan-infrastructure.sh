#!/bin/bash
# scripts/cluster/plan-infrastructure.sh
# Plan infrastructure changes
# Usage: plan-infrastructure.sh <cluster-name>

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

# Ensure initialized
if [ ! -d "$TERRAFORM_INFRA_DIR/.terraform" ]; then
	info "Not initialized, initializing first..."
	"$SCRIPT_DIR/init-infrastructure.sh" "$CLUSTER_NAME"
fi

info "Planning infrastructure changes..."

cd "$TERRAFORM_INFRA_DIR"

# Calculate relative path from terraform to cluster directory
CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"
# Plan file goes in cluster directory (relative path from terraform/)
PLAN_FILE="../clusters/$CLUSTER_NAME/terraform.tfplan"

terraform plan \
	-var-file="$CLUSTER_TFVARS" \
	-out="$PLAN_FILE"

success "Infrastructure plan created: $PLAN_FILE"
