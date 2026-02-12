#!/bin/bash
# scripts/common.sh
# Common functions for ROSA cluster management scripts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output functions
# Note: error() goes to stderr, others go to stdout by default
# Scripts that need to output data to stdout should redirect these to stderr
error() { echo -e "${RED}Error: $*${NC}" >&2; }
warn() { echo -e "${YELLOW}Warning: $*${NC}" >&2; }
info() { echo -e "${BLUE}$*${NC}" >&2; }
success() { echo -e "${GREEN}$*${NC}" >&2; }

# Get repository root directory
get_project_root() {
	git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Validate and return cluster directory path
get_cluster_dir() {
	local cluster_name="${1:-}"
	if [ -z "$cluster_name" ]; then
		error "Cluster name is required"
		exit 1
	fi

	local project_root
	project_root=$(get_project_root)
	local cluster_dir="$project_root/clusters/$cluster_name"

	if [ ! -d "$cluster_dir" ]; then
		error "Cluster directory not found: $cluster_dir"
		# shellcheck disable=SC2012
		error "Available clusters: $(ls -1 "$project_root/clusters/" 2>/dev/null | sed 's/^/  - /' || echo '  (none)')"
		exit 1
	fi

	echo "$cluster_dir"
}

# Get terraform directory
get_terraform_dir() {
	local layer="${1:-}"
	local project_root
	project_root=$(get_project_root)

	# Layer parameter is kept for backward compatibility but ignored
	# Always return terraform directory
	echo "$project_root/terraform"
}

# Check for remote backend configuration
check_backend_config() {
	if [ -n "${TF_BACKEND_CONFIG_BUCKET:-}" ]; then
		return 0
	fi
	return 1
}

# Setup backend configuration arguments for terraform init
setup_backend_config() {
	local cluster_name="${1:-}"
	local layer="${2:-infrastructure}" # Kept for backward compatibility

	if [ -z "$cluster_name" ]; then
		error "Usage: setup_backend_config <cluster_name> [layer]"
		exit 1
	fi

	local project_root
	project_root=$(get_project_root)
	local cluster_dir="$project_root/clusters/$cluster_name"

	if check_backend_config; then
		# Remote backend (S3)
		info "Using remote S3 backend..."
		echo "-backend-config=bucket=${TF_BACKEND_CONFIG_BUCKET}"
		echo "-backend-config=key=clusters/${cluster_name}/${layer}.tfstate"
		echo "-backend-config=region=${TF_BACKEND_CONFIG_REGION:-us-east-1}"
		if [ -n "${TF_BACKEND_CONFIG_DYNAMODB_TABLE:-}" ]; then
			echo "-backend-config=dynamodb_table=${TF_BACKEND_CONFIG_DYNAMODB_TABLE}"
		fi
		echo "-backend-config=encrypt=true"
	else
		# Local backend
		info "Using local backend..."
		echo "-backend-config=path=../../${cluster_dir}/${layer}.tfstate"
	fi
}

# Check required tools are installed
check_required_tools() {
	local tools=("$@")
	local missing=()

	for tool in "${tools[@]}"; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			missing+=("$tool")
		fi
	done

	if [ ${#missing[@]} -gt 0 ]; then
		error "Missing required tools: ${missing[*]}"
		error "Please install the missing tools and try again"
		exit 1
	fi
}

# Extract value from terraform.tfvars file
get_tfvar() {
	local cluster_dir="${1:-}"
	local var_name="${2:-}"
	local default_value="${3:-}"

	if [ -z "$cluster_dir" ] || [ -z "$var_name" ]; then
		error "Usage: get_tfvar <cluster_dir> <var_name> [default_value]"
		exit 1
	fi

	local tfvars_file="$cluster_dir/terraform.tfvars"
	if [ ! -f "$tfvars_file" ]; then
		echo "${default_value}"
		return
	fi

	local line
	line=$(grep -E "^${var_name}\s*=" "$tfvars_file" 2>/dev/null | head -1)
	if [ -z "$line" ]; then
		echo "${default_value}"
		return
	fi

	# Extract value (handle quoted and unquoted)
	if echo "$line" | grep -q '".*"'; then
		echo "$line" | sed -E 's/.*"([^"]+)".*/\1/'
	else
		echo "$line" | sed -E 's/.*=\s*([^"#]+).*/\1/' | sed 's/[[:space:]]*#.*//' | tr -d ' '
	fi
}
