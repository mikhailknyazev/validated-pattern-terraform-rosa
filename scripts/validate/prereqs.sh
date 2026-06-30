#!/usr/bin/env bash
# Run account + network prerequisite validation for a cluster directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [[ -z "$CLUSTER_NAME" ]]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

CLUSTER_DIR=$(get_cluster_dir "$CLUSTER_NAME")
REGION=$(get_tfvar "$CLUSTER_DIR" "region" "us-east-1")
NETWORK_TYPE=$(get_tfvar "$CLUSTER_DIR" "network_type" "public")
ZERO_EGRESS=$(get_tfvar "$CLUSTER_DIR" "zero_egress" "false")
MULTI_AZ=$(get_tfvar "$CLUSTER_DIR" "multi_az" "true")
VPC_ID=$(get_tfvar "$CLUSTER_DIR" "existing_vpc_id" "")
CW_LOGS=$(get_tfvar "$CLUSTER_DIR" "control_plane_log_cloudwatch_enabled" "false")

ACCOUNT_ARGS=(--region "$REGION")
NETWORK_ARGS=(--region "$REGION")

if [[ "$ZERO_EGRESS" == "true" ]]; then
	NETWORK_ARGS+=(--zero-egress)
fi
if [[ "$MULTI_AZ" == "true" ]]; then
	NETWORK_ARGS+=(--multi-az)
else
	NETWORK_ARGS+=(--single-az)
fi
if [[ "$CW_LOGS" == "true" ]]; then
	NETWORK_ARGS+=(--require-cloudwatch)
fi

info "Validating account prerequisites for cluster: $CLUSTER_NAME (region: $REGION)"
"$SCRIPT_DIR/account.sh" "${ACCOUNT_ARGS[@]}" || ACCOUNT_EXIT=$?
ACCOUNT_EXIT=${ACCOUNT_EXIT:-0}

NETWORK_EXIT=0
if [[ "$NETWORK_TYPE" == "existing" ]]; then
	if [[ -z "$VPC_ID" ]]; then
		error "network_type=existing but existing_vpc_id not set in terraform.tfvars"
		exit 1
	fi
	NETWORK_ARGS+=(--vpc-id "$VPC_ID")
	info "Validating BYO VPC: $VPC_ID"
	"$SCRIPT_DIR/byo-network.sh" "${NETWORK_ARGS[@]}" || NETWORK_EXIT=$?
else
	TERRAFORM_DIR="$PROJECT_ROOT/terraform"
	if [[ -d "$TERRAFORM_DIR/.terraform" ]]; then
		TF_VPC=$(cd "$TERRAFORM_DIR" && terraform output -raw vpc_id 2>/dev/null || true)
		if [[ -n "$TF_VPC" && "$TF_VPC" != "null" ]]; then
			info "Validating Terraform-managed VPC: $TF_VPC"
			"$SCRIPT_DIR/byo-network.sh" "${NETWORK_ARGS[@]}" --vpc-id "$TF_VPC" || NETWORK_EXIT=$?
		else
			info "Skipping VPC validation — run after 'make cluster.$CLUSTER_NAME.init' and apply network, or use validate-network with --vpc-id"
		fi
	else
		info "Skipping VPC validation — cluster not initialized (no terraform output yet)"
	fi
fi

if [[ "$ACCOUNT_EXIT" -ne 0 || "$NETWORK_EXIT" -ne 0 ]]; then
	error "Prerequisite validation failed"
	exit 1
fi

success "All prerequisite checks passed for cluster: $CLUSTER_NAME"
