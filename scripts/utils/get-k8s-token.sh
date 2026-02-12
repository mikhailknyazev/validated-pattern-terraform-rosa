#!/bin/bash
# scripts/utils/get-k8s-token.sh
# Get Kubernetes token via oc login with retry logic
# Usage: get-k8s-token.sh <api_url> <admin_password>
# Output: Token printed to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

API_URL="${1:-}"
ADMIN_PASSWORD="${2:-}"

if [ -z "$API_URL" ]; then
	error "Usage: $0 <api_url> <admin_password>"
	exit 1
fi

if [ -z "$ADMIN_PASSWORD" ] && [ -z "${TF_VAR_k8s_token:-}" ]; then
	error "Admin password or TF_VAR_k8s_token is required"
	exit 1
fi

# IMPORTANT: This script outputs ONLY the token to stdout.
# All other messages (info, warnings, errors) go to stderr.
# This allows callers to capture the token cleanly: TOKEN=$(get-k8s-token.sh ...)

# If token is already provided, use it (trim whitespace)
if [ -n "${TF_VAR_k8s_token:-}" ]; then
	warn "Note: Using TF_VAR_k8s_token from environment" >&2
	echo "${TF_VAR_k8s_token}" | tr -d '\n\r' | sed 's/[[:space:]]*$//'
	exit 0
fi

# Check oc CLI is available
check_required_tools oc >&2

info "Obtaining Kubernetes token via oc login..." >&2

TIMEOUT=300
ELAPSED=0
INTERVAL=10
K8S_TOKEN=""

while [ $ELAPSED -lt $TIMEOUT ]; do
	if oc login "$API_URL" --username=admin --password="$ADMIN_PASSWORD" --insecure-skip-tls-verify=true >/dev/null 2>&1 ||
		oc login "$API_URL" --username=admin --password="$ADMIN_PASSWORD" --insecure-skip-tls-verify=false >/dev/null 2>&1; then
		K8S_TOKEN_RAW=$(oc whoami --show-token 2>/dev/null || echo "")
		K8S_TOKEN=$(echo "$K8S_TOKEN_RAW" | tr -d '\n\r' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

		if [ -n "$K8S_TOKEN" ]; then
			# Only output the token to stdout (for capture by caller)
			# All messages go to stderr
			success "Successfully obtained Kubernetes token" >&2
			echo "$K8S_TOKEN"
			exit 0
		fi
	fi
	warn "Waiting for cluster to be ready... (${ELAPSED}s/${TIMEOUT}s)" >&2
	sleep $INTERVAL
	ELAPSED=$((ELAPSED + INTERVAL))
done

error "Failed to login to cluster after ${TIMEOUT} seconds" >&2
exit 1
