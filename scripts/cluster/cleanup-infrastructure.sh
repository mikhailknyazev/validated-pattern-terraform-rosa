#!/bin/bash
# scripts/cluster/cleanup-infrastructure.sh
# Sleep infrastructure (destroy with preserved resources, auto-approve, CI/CD friendly)
# This script destroys cluster resources while preserving DNS, admin password, IAM, etc.
# Used by "make sleep" target to temporarily shut down clusters for cost savings.
# Usage: cleanup-infrastructure.sh <cluster-name>

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

warn "WARNING: This will DESTROY the infrastructure!"
warn "AWS resources (cluster, VPC, IAM roles, etc.) will be deleted."

info "Setting persists_through_sleep=false and applying to sleep cluster..."

cd "$TERRAFORM_INFRA_DIR"

# Calculate relative path from terraform to cluster directory
CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"

# Remove any stale plan files that might interfere
if [ -f "$CLUSTER_DIR/terraform.tfplan" ]; then
	info "Removing stale plan file to ensure fresh apply plan..."
	rm -f "$CLUSTER_DIR/terraform.tfplan"
fi

MACHINE_POOL_ARRAY=()
while IFS= read -r resource_address; do
	[ -n "$resource_address" ] && MACHINE_POOL_ARRAY+=("$resource_address")
done < <(terraform state list -var-file="$CLUSTER_TFVARS" 2>/dev/null | grep -E "module\.cluster\.rhcs_hcp_machine_pool\.default\[" || true)

if [ ${#MACHINE_POOL_ARRAY[@]} -gt 0 ]; then
	for resource_address in "${MACHINE_POOL_ARRAY[@]}"; do
		info "Removing $resource_address from state"
		if terraform state rm -var-file="$CLUSTER_TFVARS" "$resource_address" 2>/dev/null; then
			info "Successfully removed $resource_address from state"
		else
			warn "Could not remove $resource_address from state (may not exist or already removed)"
		fi
	done
else
	info "No default machine pools found in state (may already be removed or cluster not created)"
fi

# Also remove data sources for default machine pools (they'll be cleaned up automatically)
info "Removing default machine pool data sources from Terraform state..."
MACHINE_POOL_DATA_ARRAY=()
while IFS= read -r resource_address; do
	[ -n "$resource_address" ] && MACHINE_POOL_DATA_ARRAY+=("$resource_address")
done < <(terraform state list -var-file="$CLUSTER_TFVARS" 2>/dev/null | grep -E "module\.cluster\.data\.rhcs_hcp_machine_pool\.default\[" || true)

if [ ${#MACHINE_POOL_DATA_ARRAY[@]} -gt 0 ]; then
	for resource_address in "${MACHINE_POOL_DATA_ARRAY[@]}"; do
		info "Removing $resource_address from state"
		if terraform state rm -var-file="$CLUSTER_TFVARS" "$resource_address" 2>/dev/null; then
			info "Successfully removed $resource_address from state"
		else
			warn "Could not remove $resource_address from state (may not exist or already removed)"
		fi
	done
else
	info "No default machine pool data sources found in state"
fi

# Verify removal was successful
REMAINING_POOLS=$(terraform state list -var-file="$CLUSTER_TFVARS" 2>/dev/null | grep -E "module\.cluster\.rhcs_hcp_machine_pool\.default\[" || true)
if [ -n "$REMAINING_POOLS" ]; then
	warn "Warning: Some machine pools may still be in state:"
	echo "$REMAINING_POOLS" | while IFS= read -r line; do
		warn "  - $line"
	done
	warn "Terraform may still attempt to delete these. ignore_deletion_error should handle failures gracefully."
fi

info "Applying persists_through_sleep=false to sleep cluster..."
terraform apply \
	-var-file="$CLUSTER_TFVARS" \
	-var="persists_through_sleep=false" \
	-auto-approve

success "Infrastructure resources have been destroyed"
success "Note: Default machine pools were removed from state and will be deleted automatically by ROSA when the cluster is destroyed"
success "Note: With ignore_deletion_error = true, Terraform would also handle this gracefully if state removal was skipped"
