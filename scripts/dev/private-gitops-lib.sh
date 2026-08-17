#!/usr/bin/env bash
# shellcheck disable=SC2034
# Shared helpers for in-cluster private GitOps (Gitea Git + Helm package registry).
# Sourced by scripts/dev/private-sync.sh and scripts/cluster/private-gitea.sh

set -euo pipefail

# shellcheck disable=SC1091
PRIVATE_GITOPS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${PRIVATE_GITOPS_LIB_DIR}/../common.sh"

# Constants consumed when this library is sourced (private-gitea.sh, private-sync.sh).
PRIVATE_GITOPS_DEFAULT_NAMESPACE="${PRIVATE_GITOPS_NAMESPACE:-gitea}"
PRIVATE_GITOPS_DEFAULT_ORG="${PRIVATE_GITOPS_ORG:-gitops}"
PRIVATE_GITOPS_DEFAULT_ADMIN="${PRIVATE_GITOPS_ADMIN_USER:-gitops-admin}"
PRIVATE_GITOPS_DEFAULT_REPO="${PRIVATE_GITOPS_CONFIG_REPO:-rosa-cluster-config}"

private_gitops_env_file() {
	local cluster_profile="${1:?cluster profile required}"
	local project_root
	project_root="$(get_project_root)"
	echo "${project_root}/clusters/${cluster_profile}/private-gitops.env"
}

private_gitops_cluster_profile() {
	echo "${CLUSTER_PROFILE:-${DEV_CLUSTER_NAME:-${CLUSTER_NAME:-}}}"
}

private_gitops_load_env() {
	local cluster_profile="${1:-$(private_gitops_cluster_profile)}"
	if [[ -z "${cluster_profile}" ]]; then
		error "Set CLUSTER_PROFILE or DEV_CLUSTER_NAME (Makefile cluster directory, e.g. public)"
		exit 1
	fi
	local env_file
	env_file="$(private_gitops_env_file "${cluster_profile}")"
	if [[ ! -f "${env_file}" ]]; then
		error "Private GitOps env not found: ${env_file}"
		error "Run: make cluster.${cluster_profile}.bootstrap-private (or scripts/cluster/private-gitea.sh install ${cluster_profile})"
		exit 1
	fi
	# shellcheck disable=SC1090
	source "${env_file}"
	export GITEA_INTERNAL_URL GITEA_ORG GITEA_ADMIN_USER GITEA_ADMIN_PASSWORD GITEA_NAMESPACE
	export GITEA_GIT_REPO_URL GITEA_HELM_REPO_URL GITEA_CONFIG_REPO
}

private_gitops_work_base_url() {
	echo "${GITEA_WORK_URL:-${GITEA_INTERNAL_URL}}"
}

private_gitops_stop_port_forward() {
	if [[ -n "${GITEA_PF_PID:-}" ]]; then
		kill "${GITEA_PF_PID}" 2>/dev/null || true
		unset GITEA_PF_PID
	fi
}

private_gitops_ensure_port_forward() {
	if [[ "${GITEA_SKIP_PORT_FORWARD:-false}" == "true" ]]; then
		export GITEA_WORK_URL="${GITEA_INTERNAL_URL}"
		return 0
	fi

	local work_url
	work_url="$(private_gitops_work_base_url)"
	if curl -fsS --connect-timeout 2 -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
		"${work_url}/api/v1/version" >/dev/null 2>&1; then
		export GITEA_WORK_URL="${work_url}"
		return 0
	fi

	local port="${GITEA_PORT_FORWARD_PORT:-13000}"
	local ns="${GITEA_NAMESPACE:-gitea}"
	info "Starting port-forward to gitea-http (${ns}) on 127.0.0.1:${port}..."
	oc port-forward "svc/gitea-http" -n "${ns}" "${port}:3000" >/dev/null 2>&1 &
	GITEA_PF_PID=$!
	sleep 3
	export GITEA_WORK_URL="http://127.0.0.1:${port}"
	if ! curl -fsS --connect-timeout 5 -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
		"${GITEA_WORK_URL}/api/v1/version" >/dev/null 2>&1; then
		private_gitops_stop_port_forward
		error "Gitea not reachable via port-forward on ${GITEA_WORK_URL}"
		return 1
	fi
}

private_gitops_work_git_repo_url() {
	local base
	base="$(private_gitops_work_base_url)"
	echo "${base}/${GITEA_ORG}/${GITEA_CONFIG_REPO}.git"
}

private_gitops_work_helm_repo_url() {
	local base
	base="$(private_gitops_work_base_url)"
	echo "${base}/api/packages/${GITEA_ORG}/helm"
}

private_gitops_reference_paths() {
	local project_root
	project_root="$(get_project_root)"
	export REFERENCE_HELM_CHARTS="${REFERENCE_HELM_CHARTS:-${project_root}/reference/validated-pattern-helm-charts}"
	export REFERENCE_CLUSTER_CONFIG="${REFERENCE_CLUSTER_CONFIG:-${project_root}/reference/rosa-cluster-config}"
}

private_gitops_curl_api() {
	local method="${1:?}"
	local path="${2:?}"
	shift 2
	local base
	base="$(private_gitops_work_base_url)"
	curl -fsS -X "${method}" \
		-u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
		-H "Content-Type: application/json" \
		"${base}${path}" "$@"
}

private_gitops_wait_gitea() {
	local max_attempts="${2:-60}"
	local attempt=1
	private_gitops_load_env "${1:-$(private_gitops_cluster_profile)}" 2>/dev/null || true
	private_gitops_ensure_port_forward || return 1
	local url
	url="$(private_gitops_work_base_url)"
	info "Waiting for Gitea at ${url}..."
	while [[ "${attempt}" -le "${max_attempts}" ]]; do
		if curl -fsS -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
			-o /dev/null "${url}/api/v1/version" 2>/dev/null; then
			success "Gitea is ready"
			return 0
		fi
		sleep 5
		attempt=$((attempt + 1))
	done
	error "Gitea did not become ready at ${url}"
	return 1
}

private_gitops_chart_version_from_dir() {
	local chart_dir="${1:?}"
	if [[ -f "${chart_dir}/Chart.yaml" ]]; then
		grep -E '^version:' "${chart_dir}/Chart.yaml" | head -1 | awk '{print $2}' | tr -d '"'"'"
		return 0
	fi
	echo ""
}

# Remove an existing Helm chart version so re-upload replaces content (dev loop without bumping Chart.yaml).
private_gitops_delete_helm_chart_version() {
	local chart_name="${1:?}"
	local chart_version="${2:?}"
	local base url http_code
	base="$(private_gitops_work_base_url)"
	url="${base}/api/v1/packages/${GITEA_ORG}/helm/${chart_name}/${chart_version}"
	http_code="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
		-u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
		"${url}" 2>/dev/null || echo "000")"
	case "${http_code}" in
	200 | 204)
		return 0
		;;
	404)
		# First upload — nothing to replace.
		return 0
		;;
	*)
		warn "Could not remove ${chart_name}:${chart_version} from Gitea (HTTP ${http_code})"
		return 1
		;;
	esac
}

private_gitops_package_and_upload_chart() {
	local chart_name="${1:?}"
	local chart_version="${2:?}"
	local charts_root="${3:?}"
	local chart_dir="${charts_root}/charts/${chart_name}"

	if [[ ! -d "${chart_dir}" ]]; then
		warn "Chart directory missing (skip): ${chart_dir}"
		return 1
	fi

	local local_version
	local_version="$(private_gitops_chart_version_from_dir "${chart_dir}")"
	if [[ -n "${local_version}" ]]; then
		chart_version="${local_version}"
	fi

	local tmp_dir
	tmp_dir="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '${tmp_dir}'" RETURN

	info "Packaging ${chart_name} ${chart_version}..."
	if ! helm package "${chart_dir}" --version "${chart_version}" --destination "${tmp_dir}" >/dev/null 2>&1; then
		warn "Skipping ${chart_name}: helm package failed (missing dependencies or invalid chart)"
		return 1
	fi
	local tgz="${tmp_dir}/${chart_name}-${chart_version}.tgz"
	if [[ ! -f "${tgz}" ]]; then
		warn "Skipping ${chart_name}: package artifact missing after helm package"
		return 1
	fi

	info "Uploading ${chart_name} to Gitea Helm registry..."
	local helm_upload_url
	helm_upload_url="$(private_gitops_work_helm_repo_url)"
	# Replace existing version (idempotent dev loop — edit chart without bumping Chart.yaml version).
	private_gitops_delete_helm_chart_version "${chart_name}" "${chart_version}" || true
	local attempt=1 max_attempts=3
	while [[ "${attempt}" -le "${max_attempts}" ]]; do
		if curl -fsS -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
			-X POST --upload-file "${tgz}" \
			"${helm_upload_url}/api/charts"; then
			success "Uploaded ${chart_name}:${chart_version}"
			return 0
		fi
		if [[ "${attempt}" -lt "${max_attempts}" ]]; then
			warn "Upload ${chart_name} failed (attempt ${attempt}/${max_attempts}), retrying..."
			sleep 5
		fi
		attempt=$((attempt + 1))
	done
	warn "Skipping ${chart_name}: upload to Gitea failed"
	return 1
}

private_gitops_patch_bootstrap_values() {
	local values_file="${1:?}"
	local git_url="${2:?}"
	local helm_url="${3:?}"
	local charts_root="${4:-}"

	if [[ ! -f "${values_file}" ]]; then
		error "Bootstrap values file not found: ${values_file}"
		return 1
	fi

	REFERENCE_HELM_CHARTS="${charts_root}" python3 - "${values_file}" "${git_url}" "${helm_url}" <<'PY'
import os
import re
import sys

path, git_url, helm_url = sys.argv[1:4]
charts_root = os.environ.get("REFERENCE_HELM_CHARTS", "")

with open(path, encoding="utf-8") as fh:
    content = fh.read()

# Replace GitHub / Pages URLs used in hub bootstrap values.
content = re.sub(
    r"url: https://github\.com/[^\s\"']+",
    f"url: {git_url}",
    content,
)
content = re.sub(
    r"helmRepoUrl: https?://[^\s\"']+",
    f"helmRepoUrl: {helm_url}",
    content,
)
content = re.sub(
    r"gitRepoUrl: https://github\.com/[^\s\"']+",
    f"gitRepoUrl: {git_url}",
    content,
)
content = re.sub(
    r"- https://github\.com/[^\s\"']+",
    f"- {git_url}",
    content,
)
content = re.sub(
    r"- https://rh-mobb\.github\.io/[^\s\"']+",
    f"- {helm_url}",
    content,
)

# Align bootstrap Application chart pins with local reference Chart.yaml versions (Gitea upload).
if charts_root:
    for chart in ("app-of-apps-infrastructure", "app-of-apps-application"):
        chart_yaml = os.path.join(charts_root, "charts", chart, "Chart.yaml")
        if not os.path.isfile(chart_yaml):
            continue
        with open(chart_yaml, encoding="utf-8") as ch:
            match = re.search(r"^version:\s*([^\s#]+)", ch.read(), re.MULTILINE)
        if not match:
            continue
        version = match.group(1).strip('"\'')
        content = re.sub(
            rf"(chart: {re.escape(chart)}\n(?:    .*\n)*?    targetRevision: )[\d.]+",
            rf"\g<1>{version}",
            content,
        )

with open(path, "w", encoding="utf-8") as fh:
    fh.write(content)
PY
	success "Patched bootstrap values for private GitOps: ${values_file}"
}
