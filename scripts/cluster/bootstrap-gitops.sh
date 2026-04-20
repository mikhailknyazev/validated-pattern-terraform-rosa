#!/bin/bash

# GitOps Bootstrap Script
# Bootstrap GitOps operator on ROSA HCP cluster using Helm charts
# This script is idempotent and can be run multiple times safely
#
# Usage:
#   export CLUSTER_NAME="my-cluster"
#   export CREDENTIALS_SECRET="my-cluster-credentials"
#   export AWS_REGION="us-east-1"
#   ./bootstrap-gitops.sh
#
# Or via Terraform shell_script resource with environment variables set

set -euo pipefail

# Enable command tracing to output every command (only if DEBUG is set)
if [[ "${DEBUG:-}" == "true" ]] || [[ "${DEBUG:-}" == "1" ]]; then
	set -x
fi

# Get script directory for relative paths (used for debugging/output)
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variable to store helm command for output
HELM_COMMAND_OUTPUT=""

# --- Error Handling Configuration ---
# Exit immediately if a command exits with a non-zero status.
set -e
# Ensures that ERR trap is inherited by shell functions
set -E

# --- Exit Functions ---
good_exit() {
	local message="$1"
	local helm_command="${2:-}"
	echo "INFO: $message"
	if [[ -n "${helm_command}" ]]; then
		echo "{\"status\": \"success\", \"message\": \"$message\", \"helm_command\": \"$helm_command\"}"
	else
		echo '{"status": "success", "message": "'"$message"'"}'
	fi
	exit 0
}

bad_exit() {
	local error_message="$1"
	local helm_command="${2:-}"
	echo "ERROR: $error_message" >&2
	if [[ -n "${helm_command}" ]]; then
		echo "{\"status\": \"failure\", \"message\": \"$error_message\", \"helm_command\": \"$helm_command\"}"
	else
		echo '{"status": "failure", "message": "'"$error_message"'"}'
	fi
	exit 1
}

# --- Trap Handler for Errors ---
# shellcheck disable=SC2329,SC2317
handle_error() {
	local last_command="$BASH_COMMAND"
	local line_number="${BASH_LINENO[0]}"
	bad_exit "Script failed at line $line_number executing command: '$last_command'"
}

# Set the trap: When an error occurs, call handle_error
trap 'handle_error' ERR

# --- Environment Variable Validation ---
validate_env_vars() {
	local required_vars=(
		"CLUSTER_NAME"
		"CREDENTIALS_SECRET"
		"AWS_REGION"
		"BOOTSTRAP_VALUES_FILE"
	)

	local missing_vars=()
	for var in "${required_vars[@]}"; do
		if [[ -z "${!var:-}" ]]; then
			missing_vars+=("$var")
		fi
	done

	if [[ ${#missing_vars[@]} -gt 0 ]]; then
		bad_exit "Missing required environment variables: ${missing_vars[*]}"
	fi

	# Validate values file exists
	if [[ ! -f "${BOOTSTRAP_VALUES_FILE}" ]]; then
		bad_exit "BOOTSTRAP_VALUES_FILE does not exist: ${BOOTSTRAP_VALUES_FILE}. Write values from Terraform: terraform output -raw gitops_bootstrap_hub_values > clusters/<cluster-dir>/cluster-bootstrap-values.yaml (or gitops_bootstrap_spoke_values for spoke), then export BOOTSTRAP_VALUES_FILE."
	fi

	# Validate ACM mode if specified
	if [[ -n "${ACM_MODE:-}" ]]; then
		if [[ ! "${ACM_MODE}" =~ ^(hub|spoke|noacm)$ ]]; then
			bad_exit "ACM_MODE must be one of: hub, spoke, noacm (got: ${ACM_MODE})"
		fi
	fi
}

# --- Check if API server is ready ---
check_api_server_ready() {
	local api_url="${1}"
	local max_attempts="${2:-20}"
	local sleep_time="${3:-15}"

	echo "Checking if API server is ready at ${api_url}..."

	# Check if curl is available
	if ! command -v curl &>/dev/null; then
		echo "WARNING: curl not available, skipping API server readiness check. Will proceed with login attempts."
		return 0
	fi

	local i=1

	while [[ $i -le $max_attempts ]]; do
		# Try to reach the API server health endpoints
		# Remove port from URL for health check endpoints
		local base_url="${api_url%%:*}"
		local health_url="${base_url}/healthz"

		if curl -k -s --connect-timeout 5 --max-time 10 "${health_url}" &>/dev/null ||
			curl -k -s --connect-timeout 5 --max-time 10 "${base_url}/readyz" &>/dev/null ||
			curl -k -s --connect-timeout 5 --max-time 10 "${api_url}" &>/dev/null; then
			echo "API server is ready (attempt ${i}/${max_attempts})."
			return 0
		else
			echo "API server not ready yet (attempt ${i}/${max_attempts}). Waiting ${sleep_time} seconds..."
			if [[ $i -ge $max_attempts ]]; then
				echo "WARNING: API server check timed out after ${max_attempts} attempts (${max_attempts} × ${sleep_time}s = $((max_attempts * sleep_time))s total), but continuing with login attempt..."
				return 1
			fi
			((i++))
			sleep "${sleep_time}"
		fi
	done
}

# --- Log into cluster function ---
log_into_cluster() {
	local credentials="${1}"
	local region="${2:-${AWS_REGION}}"
	local max_attempts="${3:-10}" # Increased from 5 to 10
	local sleep_time="${4:-30}"

	echo "Retrieving cluster credentials from AWS Secrets Manager (region: ${region})..."

	# Use jq to directly extract values
	local secret_string
	secret_string=$(aws secretsmanager get-secret-value \
		--secret-id "${credentials}" \
		--region "${region}" \
		--query SecretString \
		--output text)

	# Extract credentials using jq
	local url pw user
	url=$(echo "${secret_string}" | jq -r ".url")
	pw=$(echo "${secret_string}" | jq -r ".password")
	user=$(echo "${secret_string}" | jq -r ".user")

	if [[ -z "${url}" || "${url}" == "null" ]] ||
		[[ -z "${pw}" || "${pw}" == "null" ]] ||
		[[ -z "${user}" || "${user}" == "null" ]]; then
		bad_exit "Failed to extract credentials from secret ${credentials}"
	fi

	echo "Successfully retrieved AWS secret."

	# Set NO_PROXY variable for ROSA HCP
	export NO_PROXY="${NO_PROXY:-},.p3.openshiftapps.com"

	# Check if API server is ready before attempting login
	echo "Waiting for API server to be ready before attempting login..."
	check_api_server_ready "${url}" 20 15 # 20 attempts, 15 seconds each = 5 minutes max

	# Log into cluster with retry logic
	echo "Attempting cluster login to ${url}..."
	local i=1
	local login_result=""

	while [[ $i -le $max_attempts ]]; do
		if oc login "${url}" \
			--username "${user}" \
			--password "${pw}" \
			--insecure-skip-tls-verify &>/dev/null; then
			echo "Logged in to OpenShift cluster successfully."
			break
		else
			login_result=$?
			echo "Cluster login attempt ${i}/${max_attempts} failed (exit code: ${login_result}). Sleeping ${sleep_time} seconds..."

			if [[ $i -ge $max_attempts ]]; then
				bad_exit "Failed to log in to cluster after ${max_attempts} attempts."
			fi
			((i++))
			sleep "${sleep_time}"
		fi
	done

	# Extract domain from URL for Helm charts
	local domain
	domain=$(echo "${url}" | awk -F'.' '{print $2"."$3"."$4"."$5"."$6}' | awk -F':' '{print $1}')
	echo "Cluster domain: ${domain}"

	# Export domain for use in other functions
	export CLUSTER_DOMAIN="${domain}"

	# Extra sleep as the API can be jumpy after initial login post build
	sleep 60
}

# --- Check if Helm chart is already installed (idempotency) ---
check_helm_release() {
	local release_name="${1}"
	local namespace="${2}"

	if helm list -n "${namespace}" 2>/dev/null | grep -q "^${release_name}\s"; then
		local status
		status=$(helm list -n "${namespace}" -o json 2>/dev/null |
			jq -r ".[] | select(.name == \"${release_name}\") | .status" || echo "")

		if [[ "${status}" == "deployed" ]]; then
			echo "Helm release ${release_name} is already deployed in namespace ${namespace}"
			return 0
		else
			echo "Helm release ${release_name} exists but status is ${status}, will upgrade"
			return 1
		fi
	else
		echo "Helm release ${release_name} not found in namespace ${namespace}"
		return 1
	fi
}

# --- Setup Helm repository ---
setup_helm_repo() {
	local repo_name="${HELM_REPO_NAME:-vp-rosa-gitops}"
	local repo_url="${HELM_REPO_URL:-https://rh-mobb.github.io/validated-pattern-helm-charts/}"

	echo "Setting up Helm repository: ${repo_name}"

	# Add repo if it doesn't exist (idempotent)
	if helm repo list 2>/dev/null | grep -q "^${repo_name}\s"; then
		echo "Helm repository ${repo_name} already exists, updating..."
		helm repo update "${repo_name}" || true
	else
		echo "Adding Helm repository ${repo_name}..."
		helm repo add "${repo_name}" "${repo_url}" || {
			# If add fails, try to update (might already exist with different URL)
			echo "Add failed, trying to update existing repo..."
			helm repo update "${repo_name}" || true
		}
	fi

	echo "Updating all Helm repositories..."
	helm repo update
}

# --- Install GitOps for hub/standalone cluster ---
install_gitops_hub() {
	local chart_name="${HELM_CHART:-cluster-bootstrap}"
	local chart_version="${HELM_CHART_VERSION:-0.5.4}"
	local namespace="${HELM_NAMESPACE:-openshift-operators}"
	local helm_timeout="${HELM_TIMEOUT:-15m}"

	echo "=== Installing GitOps for hub/standalone cluster ==="

	# Values file from Terraform output (gitops_bootstrap_hub_values or gitops_bootstrap_spoke_values)
	local helm_args=(
		"upgrade" "--install" "${chart_name}"
		"${HELM_REPO_NAME:-vp-rosa-gitops}/${chart_name}"
		"--version" "${chart_version}"
		"--insecure-skip-tls-verify"
		"--namespace" "${namespace}"
		"--timeout" "${helm_timeout}"
		"--wait"
		"--wait-for-jobs"
		"--values" "${BOOTSTRAP_VALUES_FILE}"
	)

	# Build helm command string for output (escape quotes for JSON)
	local helm_command="helm ${helm_args[*]}"
	helm_command=$(printf '%s' "$helm_command" | sed 's/"/\\"/g')

	# Store helm command in global variable for output
	HELM_COMMAND_OUTPUT="${helm_command}"

	# Always run helm upgrade --install (it's idempotent and will handle upgrades/changes)
	# This ensures that changes to helm_chart_version, git_path, or other values are applied
	# Helm will automatically install subchart dependencies (like application-gitops) when installing from a repo
	# Using --wait and --wait-for-jobs ensures post-install hooks complete before Helm returns
	echo "Installing/Upgrading ${chart_name} chart (this may take several minutes for hooks to complete)..."
	echo "Using values file: ${BOOTSTRAP_VALUES_FILE}"

	helm "${helm_args[@]}"

	# Verify installation
	if ! helm list -n "${namespace}" 2>/dev/null | grep -q "^${chart_name}\s.*deployed"; then
		bad_exit "Helm failed to install ${chart_name} chart." "${helm_command}"
	fi

	echo "✓ Successfully installed ${chart_name} chart."
	helm list -n "${namespace}" | grep "${chart_name}" || true

	# Helm hooks with post-install create resources directly (not Jobs), so --wait-for-jobs doesn't wait for them
	# However, --wait should wait for resources to be ready if they have ready conditions
	# We'll verify that the hook resources (ArgoCD CRs) were created
	echo "Verifying post-install hooks created ArgoCD instances..."

	# Verify cluster-gitops ArgoCD instance was created (main chart)
	# Note: --wait-for-jobs waits for hook Jobs, but ArgoCD CRs aren't Jobs, so we verify separately
	echo "Verifying cluster-gitops ArgoCD instance..."
	local max_attempts=30
	local attempt=1
	while [[ $attempt -le $max_attempts ]]; do
		if oc get argocd cluster-gitops -n openshift-gitops &>/dev/null; then
			echo "✓ cluster-gitops ArgoCD instance found in openshift-gitops namespace"
			break
		else
			if [[ $attempt -ge $max_attempts ]]; then
				bad_exit "cluster-gitops ArgoCD instance not found after ${max_attempts} attempts. Post-install hook may have failed." "${helm_command}"
			else
				echo "Waiting for cluster-gitops ArgoCD instance... (attempt ${attempt}/${max_attempts})"
				sleep 5
			fi
			((attempt++))
		fi
	done

	# Verify application-gitops ArgoCD instance was created (subchart)
	echo "Verifying application-gitops ArgoCD instance..."
	attempt=1
	while [[ $attempt -le $max_attempts ]]; do
		if oc get argocd application-gitops -n application-gitops &>/dev/null; then
			echo "✓ application-gitops ArgoCD instance found in application-gitops namespace"
			break
		else
			if [[ $attempt -ge $max_attempts ]]; then
				bad_exit "application-gitops ArgoCD instance not found after ${max_attempts} attempts. Post-install hook may have failed." "${helm_command}"
			else
				echo "Waiting for application-gitops ArgoCD instance... (attempt ${attempt}/${max_attempts})"
				sleep 5
			fi
			((attempt++))
		fi
	done

	# Output helm command in JSON for Terraform
	good_exit "Successfully installed ${chart_name} chart." "${helm_command}"
}

# --- Install GitOps for spoke cluster ---
install_gitops_spoke() {
	local chart_name="${HELM_CHART_ACM_SPOKE:-cluster-bootstrap-acm-spoke}"
	local chart_version="${HELM_CHART_ACM_SPOKE_VERSION:-0.6.3}"
	local namespace="${HELM_NAMESPACE:-openshift-operators}"

	echo "=== Installing GitOps for ACM spoke cluster ==="

	# Validate required variables for spoke
	local required_spoke_vars=(
		"HUB_CREDENTIALS_SECRET"
		"ACM_REGION"
	)

	local missing_vars=()
	for var in "${required_spoke_vars[@]}"; do
		if [[ -z "${!var:-}" ]]; then
			missing_vars+=("$var")
		fi
	done

	if [[ ${#missing_vars[@]} -gt 0 ]]; then
		bad_exit "Missing required environment variables for spoke cluster: ${missing_vars[*]}"
	fi

	# Extract gitPath components for hub registration (e.g., nonprod/np-ai-1 -> environment=nonprod)
	local git_environment=""
	if [[ -n "${GIT_PATH:-}" ]]; then
		git_environment=$(echo "${GIT_PATH}" | cut -d'/' -f1)
	fi

	# STEP 1: Deploy spoke cluster components first (ArgoCD, storage, etc.)
	echo "=== STEP 1: Deploying spoke cluster components ==="

	local helm_timeout="${HELM_TIMEOUT:-15m}"

	# Values file from Terraform output (gitops_bootstrap_hub_values or gitops_bootstrap_spoke_values)
	local helm_args=(
		"upgrade" "--install" "${chart_name}"
		"${HELM_REPO_NAME:-vp-rosa-gitops}/${chart_name}"
		"--version" "${chart_version}"
		"--insecure-skip-tls-verify"
		"--create-namespace"
		"--namespace" "${namespace}"
		"--timeout" "${helm_timeout}"
		"--wait"
		"--wait-for-jobs"
		"--values" "${BOOTSTRAP_VALUES_FILE}"
	)

	# Build helm command string for output
	local helm_command="helm ${helm_args[*]}"
	helm_command=$(printf '%s' "$helm_command" | sed 's/"/\\"/g')

	# Store helm command in global variable for output
	HELM_COMMAND_OUTPUT="${helm_command}"

	# Always run helm upgrade --install (it's idempotent and will handle upgrades/changes)
	# This ensures that changes to helm_chart_version, git_path, or other values are applied
	# Helm will automatically install subchart dependencies (like application-gitops) when installing from a repo
	# Using --wait and --wait-for-jobs ensures post-install hooks complete before Helm returns
	echo "Installing/Upgrading ${chart_name} chart on spoke (this may take several minutes for hooks to complete)..."

	helm "${helm_args[@]}"

	# Verify installation
	if ! helm list -n "${namespace}" 2>/dev/null | grep -q "^${chart_name}\s.*deployed"; then
		bad_exit "Helm failed to install ${chart_name} chart on spoke cluster." "${helm_command}"
	fi

	echo "✓ Successfully installed ${chart_name} chart on spoke cluster."
	helm list -n "${namespace}" | grep "${chart_name}" || true

	# Post-install hooks should have completed (due to --wait-for-jobs), but verify ArgoCD instances were created
	echo "Verifying post-install hooks created ArgoCD instances..."

	# Verify application-gitops ArgoCD instance was created (subchart)
	# Note: --wait-for-jobs waits for hook Jobs, but ArgoCD CRs aren't Jobs, so we verify separately
	echo "Verifying application-gitops ArgoCD instance..."
	local max_attempts=30
	local attempt=1
	while [[ $attempt -le $max_attempts ]]; do
		if oc get argocd application-gitops -n application-gitops &>/dev/null; then
			echo "✓ application-gitops ArgoCD instance found in application-gitops namespace"
			break
		else
			if [[ $attempt -ge $max_attempts ]]; then
				bad_exit "application-gitops ArgoCD instance not found after ${max_attempts} attempts. Post-install hook may have failed." "${helm_command}"
			else
				echo "Waiting for application-gitops ArgoCD instance... (attempt ${attempt}/${max_attempts})"
				sleep 5
			fi
			((attempt++))
		fi
	done

	# STEP 2: Register spoke with ACM hub (if not already registered)
	echo "=== STEP 2: Registering spoke cluster with ACM hub ==="

	# Log into hub cluster
	log_into_cluster "${HUB_CREDENTIALS_SECRET}" "${ACM_REGION}"
	local hub_api_url
	hub_api_url=$(oc whoami --show-server)
	local hub_api_hostname
	hub_api_hostname=$(echo "${hub_api_url}" | awk -F'/' '{print $3}' | awk -F':' '{print $1}')
	echo "Hub API hostname: ${hub_api_hostname}"

	# Check if already registered (idempotency)
	local hub_registration_chart="${CLUSTER_NAME}-hub-registration"
	if oc get namespace "${CLUSTER_NAME}" &>/dev/null &&
		check_helm_release "${hub_registration_chart}" "${CLUSTER_NAME}"; then
		echo "Spoke cluster ${CLUSTER_NAME} already registered with hub, skipping registration."
	else
		# Deploy hub registration chart
		local hub_chart_name="${HELM_CHART_ACM_HUB_REGISTRATION:-cluster-bootstrap-acm-hub-registration}"
		local hub_chart_version="${HELM_CHART_ACM_HUB_REGISTRATION_VERSION:-0.1.0}"

		echo "Deploying ${hub_chart_name} chart to hub..."
		# shellcheck disable=SC2046
		helm upgrade --install "${hub_registration_chart}" \
			"${HELM_REPO_NAME:-vp-rosa-gitops}/${hub_chart_name}" \
			--version "${hub_chart_version}" \
			--insecure-skip-tls-verify \
			--create-namespace \
			--namespace "${CLUSTER_NAME}" \
			--set "clusterName=${CLUSTER_NAME}" \
			$(if [[ -n "${git_environment}" ]]; then echo "--set" "environment=${git_environment}"; fi)

		echo "Waiting for ACM to create import secrets for cluster ${CLUSTER_NAME}..."
		sleep 45
	fi

	# Get import manifests from hub
	echo "Retrieving import secrets from hub cluster..."

	# Check what keys exist in the secret
	echo "Available keys in ${CLUSTER_NAME}-import secret:"
	oc get secret -n "${CLUSTER_NAME}" "${CLUSTER_NAME}-import" -o jsonpath='{.data}' 2>/dev/null |
		jq -r 'keys[]' || echo "Could not list secret keys"

	# Try to get the CRDs (might be crds.yaml or crdsv1.yaml)
	local acm_crds_file="acm-crds.yaml"
	if oc get secret -n "${CLUSTER_NAME}" "${CLUSTER_NAME}-import" \
		-o jsonpath='{.data.crds\.yaml}' 2>/dev/null | base64 -d >"${acm_crds_file}" &&
		[[ -s "${acm_crds_file}" ]]; then
		echo "Successfully retrieved CRDs using crds.yaml key"
	elif oc get secret -n "${CLUSTER_NAME}" "${CLUSTER_NAME}-import" \
		-o jsonpath='{.data.crdsv1\.yaml}' 2>/dev/null | base64 -d >"${acm_crds_file}" &&
		[[ -s "${acm_crds_file}" ]]; then
		echo "Successfully retrieved CRDs using crdsv1.yaml key"
	else
		bad_exit "Failed to retrieve CRDs from import secret. Secret may not be ready yet or keys are incorrect."
	fi

	# Get the main import YAML
	local import_file="${CLUSTER_NAME}-import.yaml"
	oc get secret -n "${CLUSTER_NAME}" "${CLUSTER_NAME}-import" \
		-o jsonpath='{.data.import\.yaml}' | base64 -d >"${import_file}"

	# STEP 3: Apply ACM import manifests to spoke
	echo "=== STEP 3: Applying ACM import manifests to spoke ==="

	# Log back into spoke cluster
	log_into_cluster "${CREDENTIALS_SECRET}" "${AWS_REGION}"

	# Check if CRDs are already applied (idempotency)
	if oc get crd klusterlets.operator.open-cluster-management.io &>/dev/null; then
		echo "ACM CRDs already applied, skipping..."
	else
		echo "Applying ACM CRDs..."
		oc apply -f "${acm_crds_file}"
	fi

	# Check if cluster is already imported (idempotency)
	if oc get klusterlet klusterlet &>/dev/null; then
		echo "Klusterlet already exists, cluster may already be imported."
	else
		echo "Applying cluster import manifest..."
		oc apply -f "${import_file}"
		echo "✓ Spoke cluster import manifest applied."
		echo "Waiting for klusterlet to connect..."
		sleep 15
	fi

	# STEP 4: Verify ArgoCD integration
	echo "=== STEP 4: Verifying ArgoCD integration ==="

	# Log back into hub cluster
	log_into_cluster "${HUB_CREDENTIALS_SECRET}" "${ACM_REGION}"

	echo "Waiting for ArgoCD cluster secret to be created on hub..."
	sleep 15

	# Verify the cluster secret was created in hub ArgoCD
	if oc get secret -n openshift-gitops 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
		echo "✓ ArgoCD cluster secret created for ${CLUSTER_NAME} on hub."
	else
		echo "⚠ Warning: ArgoCD cluster secret not yet created. It may take a few moments."
	fi

	echo ""
	echo "✓ Spoke cluster ${CLUSTER_NAME} fully configured:"
	echo "  - Registered with ACM hub"
	echo "  - ArgoCD installed on spoke (openshift-gitops namespace)"
	echo "  - Spoke ArgoCD registered with hub ArgoCD (openshift-gitops namespace)"
	echo "  - ApplicationSets on hub will automatically deploy applications to this cluster"
}

# --- Install AWS Private CA Issuer (optional) ---
install_aws_privateca_issuer() {
	if [[ -z "${AWS_PRIVATE_CA_ARN:-}" ]]; then
		echo "AWS_PRIVATE_CA_ARN not set, skipping AWS Private CA Issuer installation."
		return 0
	fi

	local chart_name="${HELM_CHART_AWSPCA:-aws-privateca-issuer}"
	local chart_version="${HELM_CHART_AWSPCA_VERSION:-1.5.7}"
	local namespace="${AWSPCA_NAMESPACE:-cert-manager-operator}"
	local awspca_csv="${AWSPCA_CSV:-cert-manager-operator.v1.17.0}"
	local awspca_issuer="${AWSPCA_ISSUER:-${ZONE_NAME:-}}"

	if [[ -z "${awspca_issuer}" ]]; then
		echo "AWSPCA_ISSUER or ZONE_NAME not set, skipping AWS Private CA Issuer installation."
		return 0
	fi

	echo "=== Installing AWS Private CA Issuer ==="

	# Check if already installed (idempotency)
	if check_helm_release "${chart_name}" "${namespace}"; then
		echo "AWS Private CA Issuer chart already installed, skipping installation."
		return 0
	fi

	if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
		bad_exit "AWS_ACCOUNT_ID is required for AWS Private CA Issuer installation."
	fi

	# Use CERT_MANAGER_ROLE_ARN from Terraform output if provided, otherwise construct from cluster name
	local cert_manager_role="${CERT_MANAGER_ROLE_ARN:-arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-rosa-cert-manager}"

	echo "Installing/Upgrading ${chart_name} chart..."
	# shellcheck disable=SC2046
	helm upgrade --install "${chart_name}" \
		"${HELM_REPO_NAME:-vp-rosa-gitops}/${chart_name}" \
		--version "${chart_version}" \
		--set "certManagerRole=${cert_manager_role}" \
		--set "awsAcmPcaArn=${AWS_PRIVATE_CA_ARN}" \
		--set "csv=${awspca_csv}" \
		--set "awsPcaIssuer=${awspca_issuer}" \
		--insecure-skip-tls-verify \
		--create-namespace \
		--namespace "${namespace}" \
		--set "aws_region=${AWS_REGION}" \
		$(if [[ -n "${ECR_ACCOUNT:-}" ]]; then echo "--set" "ecr_account=${ECR_ACCOUNT}"; fi) \
		$(if [[ -n "${ECR_ACCOUNT:-}" ]]; then echo "--set" "helper-installplan-approver.ecr_account=${ECR_ACCOUNT}"; fi) \
		$(if [[ -n "${AWS_REGION:-}" ]]; then echo "--set" "helper-installplan-approver.aws_region=${AWS_REGION}"; fi)

	# Verify installation
	if ! helm list -n "${namespace}" 2>/dev/null |
		awk -v name="${chart_name}" '$1 == name && $7 == "deployed"'; then
		bad_exit "Helm failed to install ${chart_name} chart."
	fi

	echo "✓ Successfully installed ${chart_name} chart."
	helm list -A | grep -i "${chart_name}" || true
}

# --- Configure storage classes ---
configure_storage_classes() {
	echo "=== Configuring storage classes ==="

	# Check if gp3-csi-kms storage class exists and is already default
	if oc get storageclass gp3-csi-kms &>/dev/null; then
		local is_default
		is_default=$(oc get storageclass gp3-csi-kms -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' || echo "false")

		if [[ "${is_default}" == "true" ]]; then
			echo "Storage class gp3-csi-kms is already set as default, skipping."
			return 0
		fi
	fi

	# Set gp3-csi to non-default (idempotent - ignore if already set)
	echo "Patching gp3-csi storage class to be non-default..."
	oc patch storageclass gp3-csi \
		-p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' \
		2>/dev/null || true

	# Set gp3-csi-kms to default (idempotent)
	echo "Patching gp3-csi-kms storage class to be default..."
	oc patch storageclass gp3-csi-kms \
		-p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' \
		2>/dev/null || true

	echo "✓ Storage classes configured."
}

# --- Cleanup function for destroy operations ---
cleanup_acm_spoke() {
	echo "=== Cleaning up ACM resources for spoke cluster ==="

	if [[ -z "${HUB_CREDENTIALS_SECRET:-}" ]] || [[ -z "${ACM_REGION:-}" ]]; then
		echo "HUB_CREDENTIALS_SECRET or ACM_REGION not set, skipping ACM cleanup."
		return 0
	fi

	# Log into hub cluster
	log_into_cluster "${HUB_CREDENTIALS_SECRET}" "${ACM_REGION}"

	echo "Cleaning up ACM resources for spoke cluster ${CLUSTER_NAME} on hub..."

	# Delete GitOpsCluster in openshift-gitops (idempotent - ignore if not found)
	echo "Deleting GitOpsCluster ${CLUSTER_NAME}-gitops in openshift-gitops..."
	oc delete gitopscluster "${CLUSTER_NAME}-gitops" -n openshift-gitops --ignore-not-found=true || true

	# Delete GitOpsCluster in application-gitops (idempotent - ignore if not found)
	echo "Deleting GitOpsCluster ${CLUSTER_NAME}-app-gitops in application-gitops..."
	oc delete gitopscluster "${CLUSTER_NAME}-app-gitops" -n application-gitops --ignore-not-found=true || true

	# Delete ArgoCD cluster secret in openshift-gitops (targeted - only this cluster's secret)
	echo "Deleting ArgoCD cluster secret for ${CLUSTER_NAME} in openshift-gitops..."
	oc get secret -n openshift-gitops \
		-l argocd.argoproj.io/secret-type=cluster \
		-o name 2>/dev/null | while read -r secret; do
		if oc get "$secret" -n openshift-gitops -o jsonpath='{.data.name}' 2>/dev/null | base64 -d 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
			echo "  Deleting $secret..."
			oc delete "$secret" -n openshift-gitops --ignore-not-found=true || true
		fi
	done

	# Delete ArgoCD cluster secret in application-gitops (targeted - only this cluster's secret)
	echo "Deleting ArgoCD cluster secret for ${CLUSTER_NAME} in application-gitops..."
	oc get secret -n application-gitops \
		-l argocd.argoproj.io/secret-type=cluster \
		-o name 2>/dev/null | while read -r secret; do
		if oc get "$secret" -n application-gitops -o jsonpath='{.data.name}' 2>/dev/null | base64 -d 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
			echo "  Deleting $secret..."
			oc delete "$secret" -n application-gitops --ignore-not-found=true || true
		fi
	done

	# Delete application-manager addon (idempotent)
	echo "Deleting application-manager addon for ${CLUSTER_NAME}..."
	oc delete managedclusteraddon application-manager -n "${CLUSTER_NAME}" --ignore-not-found=true || true

	# Delete Placement in application-gitops (idempotent)
	echo "Deleting Placement ${CLUSTER_NAME} in application-gitops..."
	oc delete placement "${CLUSTER_NAME}" -n application-gitops --ignore-not-found=true || true

	# Delete ManagedClusterSetBinding in application-gitops (idempotent)
	echo "Deleting ManagedClusterSetBinding ${CLUSTER_NAME} in application-gitops..."
	oc delete managedclustersetbinding "${CLUSTER_NAME}" -n application-gitops --ignore-not-found=true || true

	# Delete ManagedClusterSet (idempotent)
	echo "Deleting ManagedClusterSet ${CLUSTER_NAME}..."
	oc delete managedclusterset "${CLUSTER_NAME}" --ignore-not-found=true || true

	# Delete acm-placement ConfigMap in application-gitops (idempotent)
	echo "Deleting ConfigMap acm-placement-${CLUSTER_NAME} in application-gitops..."
	oc delete configmap "acm-placement-${CLUSTER_NAME}" -n application-gitops --ignore-not-found=true || true

	# Delete ManagedCluster (idempotent)
	echo "Deleting ManagedCluster ${CLUSTER_NAME}..."
	oc delete managedcluster "${CLUSTER_NAME}" --ignore-not-found=true || true

	# Uninstall hub-registration Helm chart (idempotent)
	echo "Uninstalling hub-registration chart for ${CLUSTER_NAME}..."
	helm uninstall "${CLUSTER_NAME}-hub-registration" -n "${CLUSTER_NAME}" 2>/dev/null || true

	# Wait for cleanup to complete
	echo "Waiting for cleanup to complete..."
	sleep 10

	# Delete the spoke namespace on the hub (may contain leftover secrets/imports)
	echo "Deleting hub namespace ${CLUSTER_NAME}..."
	oc delete namespace "${CLUSTER_NAME}" --ignore-not-found=true || true

	echo "✓ ACM cleanup complete for spoke cluster ${CLUSTER_NAME}."
}

# --- Main execution ---
main() {
	echo "#########################################"
	echo "GitOps Bootstrap Script"
	echo "Current Date: $(date)"
	echo "#########################################"

	# Validate environment variables
	validate_env_vars

	# Set NO_PROXY for ROSA HCP
	export NO_PROXY="${NO_PROXY:-},.p3.openshiftapps.com"

	# Determine operation mode
	local enable="${ENABLE:-true}"
	local acm_mode="${ACM_MODE:-noacm}"

	if [[ "${enable}" != "true" ]]; then
		echo "Enable variable not set to 'true'. This is a cleanup operation."

		if [[ "${acm_mode}" == "spoke" ]]; then
			cleanup_acm_spoke
		fi

		good_exit "Bootstrap script cleanup completed."
	fi

	# Log into cluster
	log_into_cluster "${CREDENTIALS_SECRET}" "${AWS_REGION}"

	# Setup Helm repository
	setup_helm_repo

	# Install GitOps based on ACM mode
	case "${acm_mode}" in
	"spoke")
		install_gitops_spoke
		;;
	"hub" | "noacm")
		install_gitops_hub
		;;
	*)
		bad_exit "Invalid ACM_MODE: ${acm_mode}. Must be one of: hub, spoke, noacm"
		;;
	esac

	# Install AWS Private CA Issuer if configured
	install_aws_privateca_issuer

	# Configure storage classes
	configure_storage_classes

	# Output helm command if available (for spoke mode, hub mode already outputs it)
	good_exit "Cluster bootstrap completed successfully." "${HELM_COMMAND_OUTPUT}"
}

# Run main function
main "$@"
