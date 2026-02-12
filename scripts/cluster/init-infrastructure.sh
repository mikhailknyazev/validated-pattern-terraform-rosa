#!/bin/bash
# scripts/cluster/init-infrastructure.sh
# Initialize infrastructure Terraform backend
# Usage: init-infrastructure.sh <cluster-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
	error "Usage: $0 <cluster-name>"
	exit 1
fi

get_cluster_dir "$CLUSTER_NAME" >/dev/null # Validate cluster exists
TERRAFORM_INFRA_DIR=$(get_terraform_dir infrastructure)

info "Initializing infrastructure..."

cd "$TERRAFORM_INFRA_DIR"

# Setup backend config
if check_backend_config; then
	# Remote backend (S3)
	# Use -migrate-state if .terraform exists, otherwise -reconfigure
	if [ -d ".terraform" ]; then
		# shellcheck disable=SC2046
		terraform init -migrate-state -input=false \
			-backend-config="bucket=${TF_BACKEND_CONFIG_BUCKET}" \
			-backend-config="key=clusters/${CLUSTER_NAME}/infrastructure.tfstate" \
			-backend-config="region=${TF_BACKEND_CONFIG_REGION:-us-east-1}" \
			$(if [ -n "${TF_BACKEND_CONFIG_DYNAMODB_TABLE:-}" ]; then echo "-backend-config=dynamodb_table=${TF_BACKEND_CONFIG_DYNAMODB_TABLE}"; fi) \
			-backend-config="encrypt=true"
	else
		# shellcheck disable=SC2046
		terraform init -reconfigure -input=false \
			-backend-config="bucket=${TF_BACKEND_CONFIG_BUCKET}" \
			-backend-config="key=clusters/${CLUSTER_NAME}/infrastructure.tfstate" \
			-backend-config="region=${TF_BACKEND_CONFIG_REGION:-us-east-1}" \
			$(if [ -n "${TF_BACKEND_CONFIG_DYNAMODB_TABLE:-}" ]; then echo "-backend-config=dynamodb_table=${TF_BACKEND_CONFIG_DYNAMODB_TABLE}"; fi) \
			-backend-config="encrypt=true"
	fi
else
	# Local backend
	# Use -migrate-state if .terraform exists, otherwise -reconfigure
	# Use absolute path with project root
	PROJECT_ROOT=$(get_project_root)
	if [ -d ".terraform" ]; then
		terraform init -migrate-state -input=false \
			-backend-config="path=${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/infrastructure.tfstate"
	else
		terraform init -reconfigure -input=false \
			-backend-config="path=${PROJECT_ROOT}/clusters/${CLUSTER_NAME}/infrastructure.tfstate"
	fi
fi

success "Infrastructure initialized successfully"
