#!/usr/bin/env bash
# Push local reference/ clones to in-cluster Gitea (cluster-config Git + Helm packages).
#
# Usage:
#   scripts/dev/private-sync.sh preflight|sync-config|sync-charts|sync|help
#
# Requires clusters/<cluster>/private-gitops.env (from bootstrap-private or private-gitea.sh install).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/private-gitops-lib.sh"

DEV_CLUSTER_NAME="${DEV_CLUSTER_NAME:-public}"
OPERATION="${1:-help}"
DEV_CHART_FILTER="${DEV_CHART_FILTER:-}"

usage() {
	cat <<EOF
Private GitOps sync (cluster: ${DEV_CLUSTER_NAME})

Usage:
  $(basename "$0") preflight     Check Gitea env, reference clones, login
  $(basename "$0") sync-config   Push reference/rosa-cluster-config to Gitea
  $(basename "$0") sync-charts   Package and upload charts to Gitea Helm registry
  $(basename "$0") sync            sync-config + sync-charts (all charts/ in helm-charts clone)
  $(basename "$0") help

Environment:
  DEV_CLUSTER_NAME         Cluster directory name (default: public)
  REFERENCE_HELM_CHARTS    Local helm-charts clone
  REFERENCE_CLUSTER_CONFIG Local cluster-config clone
  DEV_CHART_FILTER         Comma-separated chart names (optional, charts only)

Docs: docs/guides/local-multi-repo-dev.md
EOF
}

get_git_target_branch() {
	local cluster_dir
	cluster_dir="$(get_cluster_dir "${DEV_CLUSTER_NAME}")"
	local rev
	rev="$(get_tfvar "${cluster_dir}" "gitops_git_target_revision" "main")"
	if [[ "${rev}" == "HEAD" ]]; then
		rev="main"
	fi
	echo "${rev}"
}

cmd_preflight() {
	private_gitops_reference_paths
	private_gitops_load_env "${DEV_CLUSTER_NAME}"
	private_gitops_ensure_port_forward
	# shellcheck disable=SC2064
	trap "private_gitops_stop_port_forward" EXIT

	local missing=0
	for cmd in oc helm curl git python3; do
		if ! command -v "${cmd}" >/dev/null 2>&1; then
			error "Missing: ${cmd}"
			missing=1
		fi
	done

	if [[ ! -d "${REFERENCE_CLUSTER_CONFIG}/.git" ]]; then
		error "cluster-config clone missing: ${REFERENCE_CLUSTER_CONFIG}"
		missing=1
	fi
	if [[ ! -d "${REFERENCE_HELM_CHARTS}/charts" ]]; then
		error "helm-charts clone missing: ${REFERENCE_HELM_CHARTS}"
		missing=1
	fi

	if ! oc whoami >/dev/null 2>&1; then
		warn "oc not logged in (needed for port-forward fallback; sync uses Gitea API/curl)"
	fi

	if ! curl -fsS -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" \
		"$(private_gitops_work_base_url)/api/v1/version" >/dev/null 2>&1; then
		error "Cannot reach Gitea — run bootstrap-private or check port-forward"
		missing=1
	else
		success "Gitea reachable: $(private_gitops_work_base_url)"
	fi

	if [[ "${missing}" -ne 0 ]]; then
		exit 1
	fi
	success "Preflight passed"
}

cmd_sync_config() {
	private_gitops_reference_paths
	private_gitops_load_env "${DEV_CLUSTER_NAME}"
	private_gitops_ensure_port_forward
	trap 'private_gitops_stop_port_forward' EXIT

	local branch
	branch="$(get_git_target_branch)"
	local push_url
	push_url="http://${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}@$(private_gitops_work_git_repo_url | sed 's|^http://||')"

	info "Pushing cluster-config to Gitea (${branch})..."
	(
		cd "${REFERENCE_CLUSTER_CONFIG}"
		git remote remove gitea-private 2>/dev/null || true
		git remote add gitea-private "${push_url}"
		git push gitea-private "HEAD:${branch}" --force
	)
	success "cluster-config synced to ${GITEA_GIT_REPO_URL} (branch ${branch})"
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

list_local_helm_charts() {
	local charts_root="${1:?}"
	local chart_dir name
	for chart_dir in "${charts_root}"/charts/*/; do
		[[ -d "${chart_dir}" ]] || continue
		name="$(basename "${chart_dir}")"
		echo "${name}"
	done
}

cmd_sync_charts() {
	private_gitops_reference_paths
	private_gitops_load_env "${DEV_CLUSTER_NAME}"
	private_gitops_ensure_port_forward
	trap 'private_gitops_stop_port_forward' EXIT

	local name ver uploaded=0 skipped=0
	while IFS= read -r name; do
		[[ -z "${name}" ]] && continue
		if ! chart_in_filter "${name}"; then
			continue
		fi
		ver="$(private_gitops_chart_version_from_dir "${REFERENCE_HELM_CHARTS}/charts/${name}")"
		if [[ -z "${ver}" ]]; then
			warn "Skipping ${name}: no version in Chart.yaml"
			skipped=$((skipped + 1))
			continue
		fi
		if private_gitops_package_and_upload_chart "${name}" "${ver}" "${REFERENCE_HELM_CHARTS}"; then
			uploaded=$((uploaded + 1))
		else
			skipped=$((skipped + 1))
		fi
	done < <(list_local_helm_charts "${REFERENCE_HELM_CHARTS}")

	if [[ "${uploaded}" -eq 0 ]]; then
		error "No charts uploaded from ${REFERENCE_HELM_CHARTS}/charts"
		exit 1
	fi
	if [[ "${skipped}" -gt 0 ]]; then
		warn "${skipped} chart(s) skipped (see warnings above)"
	fi
	success "Helm charts synced to ${GITEA_HELM_REPO_URL} (${uploaded} uploaded)"
}

cmd_sync() {
	cmd_sync_config
	cmd_sync_charts
}

case "${OPERATION}" in
help | --help | -h)
	usage
	;;
preflight)
	cmd_preflight
	;;
sync-config)
	cmd_sync_config
	;;
sync-charts)
	cmd_sync_charts
	;;
sync)
	cmd_sync
	;;
*)
	error "Unknown operation: ${OPERATION}"
	usage
	exit 1
	;;
esac
