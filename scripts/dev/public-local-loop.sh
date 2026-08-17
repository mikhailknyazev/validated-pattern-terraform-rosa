#!/usr/bin/env bash
# Local multi-repo development loop for public (or any) cluster profile.
# Optional escape hatch: helm apply-local without Gitea/Argo (see docs/guides/local-multi-repo-dev.md).
#
# Usage:
#   scripts/dev/public-local-loop.sh preflight|render|apply-local|verify|help
#
# See docs/guides/local-multi-repo-dev.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common.sh"

PROJECT_ROOT="$(get_project_root)"
DEV_CLUSTER_NAME="${DEV_CLUSTER_NAME:-public}"
REFERENCE_HELM_CHARTS="${REFERENCE_HELM_CHARTS:-${PROJECT_ROOT}/reference/validated-pattern-helm-charts}"
REFERENCE_CLUSTER_CONFIG="${REFERENCE_CLUSTER_CONFIG:-${PROJECT_ROOT}/reference/rosa-cluster-config}"
DEV_RENDER_DIR="${DEV_RENDER_DIR:-${PROJECT_ROOT}/clusters/${DEV_CLUSTER_NAME}/logs/dev-render}"
DEV_DRY_RUN="${DEV_DRY_RUN:-false}"
DEV_HELM_TIMEOUT="${DEV_HELM_TIMEOUT:-15m}"
DEV_CHART_FILTER="${DEV_CHART_FILTER:-}"

OPERATION="${1:-help}"

usage() {
	cat <<EOF
Local multi-repo GitOps dev loop (cluster: ${DEV_CLUSTER_NAME})

Usage:
  $(basename "$0") preflight     Check tools, reference clones, infrastructure.yaml
  $(basename "$0") render         helm template each chart to DEV_RENDER_DIR
  $(basename "$0") apply-local  helm upgrade --install from local chart dirs
  $(basename "$0") verify         Check platform metadata (+ ESO when listed)
  $(basename "$0") help           Show this help

Environment:
  DEV_CLUSTER_NAME           Cluster directory (default: public)
  REFERENCE_HELM_CHARTS      Local helm-charts clone
  REFERENCE_CLUSTER_CONFIG   Local cluster-config clone
  DEV_CHART_FILTER           Comma-separated chart names (optional)
  DEV_RENDER_DIR             Render output directory
  DEV_DRY_RUN                true = print helm commands only (apply-local)
  DEV_HELM_TIMEOUT           Helm timeout per chart (default: 15m)

Docs: docs/guides/local-multi-repo-dev.md
EOF
}

get_infrastructure_yaml() {
	local cluster_dir
	cluster_dir="$(get_cluster_dir "${DEV_CLUSTER_NAME}")"
	local git_path
	git_path="$(get_tfvar "${cluster_dir}" "gitops_git_path" "")"
	if [[ -z "${git_path}" ]]; then
		error "gitops_git_path not set in ${cluster_dir}/terraform.tfvars"
		exit 1
	fi
	local infra_file="${REFERENCE_CLUSTER_CONFIG}/${git_path}/infrastructure.yaml"
	if [[ ! -f "${infra_file}" ]]; then
		error "infrastructure.yaml not found: ${infra_file}"
		error "Clone cluster-config to reference/ and align gitops_git_path"
		exit 1
	fi
	echo "${infra_file}"
}

chart_in_filter() {
	local chart_name="$1"
	if [[ -z "${DEV_CHART_FILTER}" ]]; then
		return 0
	fi
	local IFS=','
	local item
	for item in ${DEV_CHART_FILTER}; do
		item="$(echo "${item}" | xargs)"
		if [[ "${item}" == "${chart_name}" ]]; then
			return 0
		fi
	done
	return 1
}

parse_infrastructure_entries() {
	local infra_file="$1"
	python3 - "${infra_file}" <<'PY'
import json
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: PyYAML required (pip install pyyaml)\n")
    sys.exit(1)

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    doc = yaml.safe_load(fh) or {}

for entry in doc.get("infrastructure") or []:
    chart = entry.get("chart")
    if not chart:
        continue
    payload = {
        "chart": chart,
        "namespace": entry.get("namespace") or "default",
        "targetRevision": entry.get("targetRevision"),
        "values": entry.get("values") or {},
    }
    print(json.dumps(payload))
PY
}

write_values_file() {
	local values_json="$1"
	local out_file="$2"
	python3 - "${values_json}" "${out_file}" <<'PY'
import json
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: PyYAML required (pip install pyyaml)\n")
    sys.exit(1)

values = json.loads(sys.argv[1])
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    yaml.safe_dump(values, fh, default_flow_style=False)
PY
}

local_chart_path() {
	local chart_name="$1"
	echo "${REFERENCE_HELM_CHARTS}/charts/${chart_name}"
}

cmd_preflight() {
	info "Preflight for cluster: ${DEV_CLUSTER_NAME}"

	local missing=0
	for cmd in oc helm python3; do
		if ! command -v "${cmd}" >/dev/null 2>&1; then
			error "Missing required command: ${cmd}"
			missing=1
		fi
	done

	if ! python3 -c "import yaml" 2>/dev/null; then
		error "Python PyYAML not installed (pip install pyyaml)"
		missing=1
	fi

	if [[ ! -d "${REFERENCE_HELM_CHARTS}/charts" ]]; then
		error "Helm charts clone missing: ${REFERENCE_HELM_CHARTS}"
		error "  git clone https://github.com/rh-mobb/validated-pattern-helm-charts.git ${REFERENCE_HELM_CHARTS}"
		missing=1
	fi

	if [[ ! -d "${REFERENCE_CLUSTER_CONFIG}" ]]; then
		error "cluster-config clone missing: ${REFERENCE_CLUSTER_CONFIG}"
		error "  git clone https://github.com/rh-mobb/rosa-cluster-config.git ${REFERENCE_CLUSTER_CONFIG}"
		missing=1
	fi

	local infra_file
	infra_file="$(get_infrastructure_yaml)"
	success "Found infrastructure manifest: ${infra_file}"

	local count=0
	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		local chart namespace
		chart="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chart"])')"
		namespace="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["namespace"])')"
		if chart_in_filter "${chart}"; then
			local chart_dir
			chart_dir="$(local_chart_path "${chart}")"
			if [[ ! -d "${chart_dir}" ]]; then
				error "Local chart directory missing: ${chart_dir}"
				missing=1
			else
				info "  chart=${chart} namespace=${namespace} path=${chart_dir}"
			fi
			count=$((count + 1))
		fi
	done < <(parse_infrastructure_entries "${infra_file}")

	if [[ "${count}" -eq 0 ]]; then
		warn "No infrastructure charts matched DEV_CHART_FILTER"
	fi

	if command -v oc >/dev/null 2>&1; then
		if oc whoami >/dev/null 2>&1; then
			success "oc logged in as $(oc whoami)"
		else
			warn "oc not logged in — run: make cluster.${DEV_CLUSTER_NAME}.login"
		fi
	fi

	if [[ "${missing}" -ne 0 ]]; then
		exit 1
	fi
	success "Preflight passed (${count} chart(s) in scope)"
}

cmd_render() {
	local infra_file
	infra_file="$(get_infrastructure_yaml)"
	mkdir -p "${DEV_RENDER_DIR}"
	info "Rendering to ${DEV_RENDER_DIR}"

	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		local chart namespace values_json
		chart="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chart"])')"
		namespace="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["namespace"])')"
		values_json="$(echo "${line}" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("values") or {}))')"

		if ! chart_in_filter "${chart}"; then
			continue
		fi

		local chart_dir
		chart_dir="$(local_chart_path "${chart}")"
		if [[ ! -d "${chart_dir}" ]]; then
			error "Chart not found: ${chart_dir}"
			exit 1
		fi

		local values_file="${DEV_RENDER_DIR}/${chart}-values.yaml"
		local out_file="${DEV_RENDER_DIR}/${chart}.yaml"
		write_values_file "${values_json}" "${values_file}"

		info "Rendering ${chart} -> ${out_file}"
		helm template "${chart}" "${chart_dir}" \
			--namespace "${namespace}" \
			-f "${values_file}" \
			>"${out_file}"
	done < <(parse_infrastructure_entries "${infra_file}")

	success "Render complete: ${DEV_RENDER_DIR}"
}

cmd_apply_local() {
	if ! oc whoami >/dev/null 2>&1; then
		error "Not logged in. Run: make cluster.${DEV_CLUSTER_NAME}.login"
		exit 1
	fi

	local infra_file
	infra_file="$(get_infrastructure_yaml)"
	local tmp_dir
	tmp_dir="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '${tmp_dir}'" EXIT

	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		local chart namespace values_json
		chart="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chart"])')"
		namespace="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["namespace"])')"
		values_json="$(echo "${line}" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("values") or {}))')"

		if ! chart_in_filter "${chart}"; then
			continue
		fi

		local chart_dir
		chart_dir="$(local_chart_path "${chart}")"
		if [[ ! -d "${chart_dir}" ]]; then
			error "Chart not found: ${chart_dir}"
			exit 1
		fi

		local values_file="${tmp_dir}/${chart}-values.yaml"
		write_values_file "${values_json}" "${values_file}"

		local helm_cmd=(
			helm upgrade --install "${chart}" "${chart_dir}"
			--namespace "${namespace}"
			--create-namespace
			-f "${values_file}"
			--timeout "${DEV_HELM_TIMEOUT}"
			--wait=false
		)

		info "Applying ${chart} to namespace ${namespace}"
		if [[ "${DEV_DRY_RUN}" == "true" ]]; then
			printf 'DRY_RUN: %q ' "${helm_cmd[@]}"
			echo
			continue
		fi

		"${helm_cmd[@]}"
	done < <(parse_infrastructure_entries "${infra_file}")

	success "Local apply complete (DEV_DRY_RUN=${DEV_DRY_RUN})"
}

cmd_verify() {
	if ! oc whoami >/dev/null 2>&1; then
		error "Not logged in. Run: make cluster.${DEV_CLUSTER_NAME}.login"
		exit 1
	fi

	local failed=0
	if oc get configmap rosa-platform-metadata -n openshift-gitops >/dev/null 2>&1; then
		success "ConfigMap rosa-platform-metadata present in openshift-gitops"
		oc get configmap rosa-platform-metadata -n openshift-gitops -o yaml | head -20
	else
		error "Missing ConfigMap rosa-platform-metadata — run make cluster.${DEV_CLUSTER_NAME}.bootstrap"
		failed=1
	fi

	local infra_file
	infra_file="$(get_infrastructure_yaml)"
	local has_eso=0
	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		local chart
		chart="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chart"])')"
		if [[ "${chart}" == "external-secrets-operator" ]]; then
			has_eso=1
		fi
	done < <(parse_infrastructure_entries "${infra_file}")

	if [[ "${has_eso}" -eq 1 ]]; then
		local ready
		ready="$(oc get clustersecretstore aws-secrets-manager \
			-o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
		if [[ "${ready}" == "True" ]]; then
			success "ClusterSecretStore aws-secrets-manager is Ready"
		else
			warn "ClusterSecretStore aws-secrets-manager not Ready (status=${ready:-missing})"
			failed=1
		fi
	fi

	if [[ "${failed}" -ne 0 ]]; then
		exit 1
	fi
	success "Verification passed"
}

case "${OPERATION}" in
help | --help | -h)
	usage
	;;
preflight)
	cmd_preflight
	;;
render)
	cmd_render
	;;
apply-local | apply)
	cmd_apply_local
	;;
verify)
	cmd_verify
	;;
*)
	error "Unknown operation: ${OPERATION}"
	usage
	exit 1
	;;
esac
