#!/bin/bash
# Get admin password from AWS Secrets Manager or environment variable
# Usage: source ./scripts/get-admin-password.sh <infrastructure_directory>
#        or: ADMIN_PASSWORD=$(./scripts/get-admin-password.sh <infrastructure_directory>)
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

echo -e "${BLUE}  Reading secret ARN from $INFRA_DIR...${NC}" >&2

# Get secret ARN from Terraform output
SECRET_ARN=$(cd "$INFRA_DIR" && terraform output -raw admin_password_secret_arn 2>&1)
EXIT_CODE=$?

echo -e "${BLUE}  Secret ARN lookup exit code: $EXIT_CODE${NC}" >&2

if [ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != "null" ]; then
	echo -e "${BLUE}  Secret ARN value: $SECRET_ARN${NC}" >&2
fi

# Check if output is a valid ARN (starts with arn:aws:secretsmanager:)
if [ $EXIT_CODE -ne 0 ] || [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "null" ] || ! echo "$SECRET_ARN" | grep -qE "^arn:aws:secretsmanager:"; then
	echo -e "${YELLOW}  Secret ARN not found or invalid${NC}" >&2
	SECRET_ARN=""

	# Check for override password
	if [ -n "${TF_VAR_admin_password_override:-}" ]; then
		echo -e "${BLUE}  Using TF_VAR_admin_password_override${NC}" >&2
		ADMIN_PASSWORD="$TF_VAR_admin_password_override"
	else
		echo -e "${YELLOW}Warning: admin_password_secret_arn not found in infrastructure state.${NC}" >&2
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

	# Retrieve password from AWS Secrets Manager
	ADMIN_PASSWORD=$(aws secretsmanager get-secret-value \
		--secret-id "$SECRET_ARN" \
		--region "$SECRET_REGION" \
		--query SecretString \
		--output text 2>&1 || echo "")

	if [ -z "$ADMIN_PASSWORD" ]; then
		echo -e "${YELLOW}Error: Failed to retrieve admin password from Secrets Manager.${NC}" >&2
		echo -e "${YELLOW}Secret ARN: $SECRET_ARN${NC}" >&2
		echo -e "${YELLOW}Region: $SECRET_REGION${NC}" >&2
		echo -e "${YELLOW}You may need to:${NC}" >&2
		echo -e "${YELLOW}  1. Ensure AWS credentials are configured${NC}" >&2
		echo -e "${YELLOW}  2. Ensure you have permission to read the secret${NC}" >&2
		echo -e "${YELLOW}  3. Or set TF_VAR_admin_password_override environment variable${NC}" >&2
		exit 1
	else
		echo -e "${GREEN}  Successfully retrieved admin password${NC}" >&2
	fi
fi

# Output password (if executed directly) or set environment variable (if sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	# Script is being executed directly, output the password
	echo "$ADMIN_PASSWORD"
else
	# Script is being sourced, export the variable
	export ADMIN_PASSWORD
fi
