#!/usr/bin/env bash
# Purpose: Mode A entry point for one-run device-code access to a ROSA API.
# What this is not: This path has no durable token store and does not create identity or RBAC configuration.
# Prerequisites: Copy common/ with this path; provide oc, kubectl oidc-login, GNU timeout and reviewed environment values.
# Authoritative references:
# - https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
# - https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code
# Covers: env:SCRIPT_DIR, env:DEFAULT_COMMON_DIR, env:COMMON_DIR, env:AUTH_LIBRARY, env:ROSA_COMMON_DIR, env:ENTRA_TENANT_ID, env:ENTRA_PUBLIC_CLIENT_ID, env:ROSA_API_ENDPOINT, env:ROSA_CLUSTER_CA_B64, env:ROSA_KUBECONFIG, env:OIDC_TOKEN_CACHE_DIR, env:ROSA_AUTH_TIMEOUT_SECONDS, env:ROSA_HOME, env:ROSA_AUTH_SKIP_KUBECONFIG_WRITE, --help
# Does: Fixes Mode A scope and exposes only prepare, whoami, run, status and cleanup.
# Why: A path-specific entry point removes a runtime security-mode switch and excludes durable-cache dependencies.
# Change: Copying a different specific path changes token custody and the available command set.
# Trap: Omitting common/ or pairing this script with a template that requests offline_access is refused before authentication.
# Evidence: https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md

set -euo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_COMMON_DIR="${SCRIPT_DIR}/../../common"
COMMON_DIR="${ROSA_COMMON_DIR:-${DEFAULT_COMMON_DIR}}"
AUTH_LIBRARY="${COMMON_DIR}/rosa-auth-common.sh"
if [[ ! -r "${AUTH_LIBRARY}" ]]; then
	printf 'rosa-auth: common library missing: %s; copy common/ with this path or set ROSA_COMMON_DIR\n' "${AUTH_LIBRARY}" >&2
	exit 66
fi
# shellcheck source=examples/ci-external-auth-device-code/common/rosa-auth-common.sh
source "${AUTH_LIBRARY}"

usage() {
	cat <<'EOF'
Usage: rosa-auth.sh <prepare|whoami|run|status|cleanup> [-- oc-args...]

Required environment:
  ENTRA_TENANT_ID             Entra tenant identifier
  ENTRA_PUBLIC_CLIENT_ID      Public-client application accepted by ROSA
  ROSA_API_ENDPOINT           ROSA API DNS name without https://
  ROSA_CLUSTER_CA_B64         Base64 cluster CA; insecure TLS is unsupported

Optional environment:
  ROSA_KUBECONFIG             Generated kubeconfig (default /tmp/rosa-exec-kubeconfig)
  OIDC_TOKEN_CACHE_DIR        Job-local token directory (default /tmp/rosa-oidc-cache)
  ROSA_AUTH_TIMEOUT_SECONDS   Maximum device-code wait (default 300)
  ROSA_HOME                   HOME for oc (default /tmp)
  ROSA_AUTH_SKIP_KUBECONFIG_WRITE  1 = use the reviewed file already at ROSA_KUBECONFIG
  ROSA_COMMON_DIR             Override the expected ../../common directory

Mode A requests no offline_access scope and persists nothing outside this job.
EOF
}

cmd_prepare() {
	rosa_auth_require_env ENTRA_TENANT_ID ENTRA_PUBLIC_CLIENT_ID ROSA_API_ENDPOINT ROSA_CLUSTER_CA_B64
	rosa_auth_require_cmds oc kubectl timeout
	umask 077
	rosa_auth_wipe_token_dir
	rosa_auth_prepare_token_dir
	rosa_auth_write_kubeconfig A
	printf 'rosa-auth: prepared mode=A kubeconfig=%s token_dir=%s\n' \
		"$(rosa_auth_kubeconfig_path)" "$(rosa_auth_token_dir)"
}

cmd_whoami() {
	rosa_auth_bounded_oc auth whoami
}

cmd_run() {
	if [[ "${1:-}" == -- ]]; then
		shift
	fi
	if [[ "$#" -eq 0 ]]; then
		printf 'rosa-auth: run requires oc arguments\n' >&2
		return 64
	fi
	rosa_auth_bounded_oc "$@"
}

cmd_status() {
	printf 'mode=A\n'
	printf 'kubeconfig=%s\n' "$(rosa_auth_kubeconfig_path)"
	printf 'token_dir=%s\n' "$(rosa_auth_token_dir)"
}

cmd_cleanup() {
	rosa_auth_wipe_token_dir
	printf 'rosa-auth: removed job-local oidc-login state\n'
}

main() {
	rosa_auth_trace_off
	umask 077
	local command_name="${1:-}"
	if [[ -z "${command_name}" || "${command_name}" == -h || "${command_name}" == --help ]]; then
		usage
		return 0
	fi
	shift || true
	case "${command_name}" in
	prepare) cmd_prepare ;;
	whoami) cmd_whoami ;;
	run) cmd_run "$@" ;;
	status) cmd_status ;;
	cleanup) cmd_cleanup ;;
	*)
		usage >&2
		return 64
		;;
	esac
}

main "$@"
