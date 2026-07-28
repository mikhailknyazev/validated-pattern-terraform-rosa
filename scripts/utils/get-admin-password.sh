#!/bin/bash
# Get admin password from AWS Secrets Manager or environment variable
# Usage: source ./scripts/utils/get-admin-password.sh <infrastructure_directory>
#        or: ADMIN_PASSWORD=$(./scripts/utils/get-admin-password.sh <infrastructure_directory>)
#
# Single source of truth: cluster credentials secret ({cluster_name}-credentials) JSON:
#   {"user":"...","password":"...","url":"..."}
# Falls back to admin_password_secret_arn (alias) and plain-string secrets for migration.
#
# Sets ADMIN_PASSWORD environment variable if sourced, or outputs password if executed directly

set -euo pipefail

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

INFRA_DIR="${1:-}"

if [ -z "$INFRA_DIR" ]; then
	echo -e "${YELLOW}Error: Infrastructure directory argument required${NC}" >&2
	echo "Usage: $0 <infrastructure_directory>" >&2
	exit 1
fi

if [ ! -d "$INFRA_DIR" ]; then
	echo -e "${YELLOW}Error: Infrastructure directory does not exist: $INFRA_DIR${NC}" >&2
	exit 1
fi

# Extract password from Secrets Manager payload.
# Prefer JSON .password (cluster credentials secret); fall back to plain string (legacy admin-password secret).
extract_password_from_secret_string() {
	local secret_string="$1"
	local password=""

	if command -v jq >/dev/null 2>&1; then
		password=$(echo "$secret_string" | jq -r '.password // empty' 2>/dev/null || true)
	fi

	if [ -n "$password" ] && [ "$password" != "null" ]; then
		echo "$password"
		return 0
	fi

	# Legacy plain-string secret (rosa-hcp-*-admin-password) or jq unavailable / non-JSON
	if echo "$secret_string" | grep -qE '^\{'; then
		echo -e "${YELLOW}Error: Secret looks like JSON but .password could not be extracted. Is jq installed?${NC}" >&2
		return 1
	fi

	echo "$secret_string"
}

lookup_secret_arn() {
	local output_name="$1"
	local value
	local exit_code=0

	value=$(cd "$INFRA_DIR" && terraform output -raw "$output_name" 2>&1) || exit_code=$?

	if [ "$exit_code" -ne 0 ] || [ -z "$value" ] || [ "$value" = "null" ] || ! echo "$value" | grep -qE "^arn:aws:secretsmanager:"; then
		return 1
	fi

	echo "$value"
}

echo -e "${BLUE}  Reading cluster credentials secret ARN from $INFRA_DIR...${NC}" >&2

SECRET_ARN=""
if SECRET_ARN=$(lookup_secret_arn "cluster_credentials_secret_arn"); then
	echo -e "${BLUE}  Using cluster_credentials_secret_arn${NC}" >&2
elif SECRET_ARN=$(lookup_secret_arn "admin_password_secret_arn"); then
	echo -e "${BLUE}  Using admin_password_secret_arn (alias / legacy)${NC}" >&2
else
	SECRET_ARN=""
fi

if [ -n "$SECRET_ARN" ]; then
	echo -e "${BLUE}  Secret ARN value: $SECRET_ARN${NC}" >&2
fi

if [ -z "$SECRET_ARN" ]; then
	echo -e "${YELLOW}  Secret ARN not found or invalid${NC}" >&2

	# Check for override password
	if [ -n "${TF_VAR_admin_password_override:-}" ]; then
		echo -e "${BLUE}  Using TF_VAR_admin_password_override${NC}" >&2
		ADMIN_PASSWORD="$TF_VAR_admin_password_override"
	else
		echo -e "${YELLOW}Warning: cluster_credentials_secret_arn not found in infrastructure state.${NC}" >&2
		echo -e "${YELLOW}Infrastructure may already be destroyed or never created.${NC}" >&2
		echo -e "${YELLOW}You can:${NC}" >&2
		echo -e "${YELLOW}  1. Set TF_VAR_admin_password_override to provide password manually${NC}" >&2
		echo -e "${YELLOW}  2. Set TF_VAR_k8s_token to provide token directly${NC}" >&2
		ADMIN_PASSWORD=""
	fi
else
	echo -e "${BLUE}  Valid secret ARN found, retrieving password...${NC}" >&2

	# Check if AWS CLI is available
	if ! command -v aws >/dev/null 2>&1; then
		echo -e "${YELLOW}Error: AWS CLI not found. Required to retrieve admin password from Secrets Manager.${NC}" >&2
		echo -e "${YELLOW}Install AWS CLI: https://aws.amazon.com/cli/${NC}" >&2
		exit 1
	fi

	# Extract region from ARN (format: arn:aws:secretsmanager:<region>:<account-id>:secret:<name>)
	SECRET_REGION=$(echo "$SECRET_ARN" | cut -d':' -f4)

	if [ -z "$SECRET_REGION" ]; then
		echo -e "${YELLOW}Error: Could not extract region from secret ARN: $SECRET_ARN${NC}" >&2
		exit 1
	fi

	# Retrieve secret payload from AWS Secrets Manager
	SECRET_STRING=$(aws secretsmanager get-secret-value \
		--secret-id "$SECRET_ARN" \
		--region "$SECRET_REGION" \
		--query SecretString \
		--output text 2>&1 || echo "")

	if [ -z "$SECRET_STRING" ]; then
		echo -e "${YELLOW}Error: Failed to retrieve admin password from Secrets Manager.${NC}" >&2
		echo -e "${YELLOW}Secret ARN: $SECRET_ARN${NC}" >&2
		echo -e "${YELLOW}Region: $SECRET_REGION${NC}" >&2
		echo -e "${YELLOW}You may need to:${NC}" >&2
		echo -e "${YELLOW}  1. Ensure AWS credentials are configured${NC}" >&2
		echo -e "${YELLOW}  2. Ensure you have permission to read the secret${NC}" >&2
		echo -e "${YELLOW}  3. Or set TF_VAR_admin_password_override environment variable${NC}" >&2
		exit 1
	fi

	if ! ADMIN_PASSWORD=$(extract_password_from_secret_string "$SECRET_STRING"); then
		exit 1
	fi

	if [ -z "$ADMIN_PASSWORD" ]; then
		echo -e "${YELLOW}Error: Secret was retrieved but password was empty.${NC}" >&2
		exit 1
	fi

	echo -e "${GREEN}  Successfully retrieved admin password${NC}" >&2
fi

# Output password (if executed directly) or set environment variable (if sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	# Script is being executed directly, output the password
	echo "$ADMIN_PASSWORD"
else
	# Script is being sourced, export the variable
	export ADMIN_PASSWORD
fi
