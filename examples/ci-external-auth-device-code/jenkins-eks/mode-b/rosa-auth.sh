#!/usr/bin/env bash
# Purpose: Mode B entry point for refresh-capable device-code access to a ROSA API.
# What this is not: This path does not create the Entra app, ROSA provider, RBAC, secret or IAM role.
# Prerequisites: Copy common/ with this path; provide oc, kubectl oidc-login, GNU timeout, AWS CLI, tar, gzip and base64.
# Authoritative references:
# - https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
# - https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/index.html
# Covers: env:SCRIPT_DIR, env:DEFAULT_COMMON_DIR, env:COMMON_DIR, env:AUTH_LIBRARY, env:CACHE_LIBRARY, env:ROSA_COMMON_DIR, env:ENTRA_TENANT_ID, env:ENTRA_PUBLIC_CLIENT_ID, env:ROSA_API_ENDPOINT, env:ROSA_CLUSTER_CA_B64, env:ROSA_KUBECONFIG, env:OIDC_TOKEN_CACHE_DIR, env:ROSA_AUTH_TIMEOUT_SECONDS, env:ROSA_HOME, env:ROSA_AUTH_SKIP_KUBECONFIG_WRITE, env:AWS_REGION, env:ROSA_B_SECRET_ID, env:ROSA_B_PERSIST, env:ROSA_B_FP_FILE, --help
# Does: Fixes Mode B scope and exposes prepare, whoami, run, seed, persist, status and cleanup against one Secrets Manager object.
# Why: A path-specific entry point makes refresh custody explicit and removes backend and security-mode switches.
# Change: Copying a different path changes token custody and the available command set.
# Trap: Omitting either common library or pairing this script with a template without offline_access is refused before authentication.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/index.html

set -euo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_COMMON_DIR="${SCRIPT_DIR}/../../common"
COMMON_DIR="${ROSA_COMMON_DIR:-${DEFAULT_COMMON_DIR}}"
AUTH_LIBRARY="${COMMON_DIR}/rosa-auth-common.sh"
CACHE_LIBRARY="${COMMON_DIR}/rosa-cache-common.sh"
if [[ ! -r "${AUTH_LIBRARY}" || ! -r "${CACHE_LIBRARY}" ]]; then
	printf 'rosa-auth: common libraries missing under %s; copy common/ with this path or set ROSA_COMMON_DIR\n' "${COMMON_DIR}" >&2
	exit 66
fi
# shellcheck source=examples/ci-external-auth-device-code/common/rosa-auth-common.sh
source "${AUTH_LIBRARY}"
# shellcheck source=examples/ci-external-auth-device-code/common/rosa-cache-common.sh
source "${CACHE_LIBRARY}"

usage() {
	cat <<'EOF'
Usage: rosa-auth.sh <prepare|whoami|run|seed|persist|status|cleanup> [-- oc-args...]

Required environment:
  ENTRA_TENANT_ID             Entra tenant identifier
  ENTRA_PUBLIC_CLIENT_ID      Public-client application accepted by ROSA
  ROSA_API_ENDPOINT           ROSA API DNS name without https://
  ROSA_CLUSTER_CA_B64         Base64 cluster CA; insecure TLS is unsupported
  AWS_REGION                  Region containing the cache secret
  ROSA_B_SECRET_ID            Secrets Manager name or ARN

Optional environment:
  ROSA_B_PERSIST              auto (default) or never
  ROSA_KUBECONFIG             Generated kubeconfig (default /tmp/rosa-exec-kubeconfig)
  OIDC_TOKEN_CACHE_DIR        Job-local token directory (default /tmp/rosa-oidc-cache)
  ROSA_AUTH_TIMEOUT_SECONDS   Maximum device-code wait (default 300)
  ROSA_HOME                   HOME for oc (default /tmp)
  ROSA_AUTH_SKIP_KUBECONFIG_WRITE  1 = use the reviewed file already at ROSA_KUBECONFIG
  ROSA_COMMON_DIR             Override the expected ../../common directory

The script never prints the token archive, secret value or token material.
EOF
}

cmd_prepare() {
	rosa_auth_require_env ENTRA_TENANT_ID ENTRA_PUBLIC_CLIENT_ID ROSA_API_ENDPOINT ROSA_CLUSTER_CA_B64
	rosa_auth_require_cmds oc kubectl timeout aws tar gzip base64
	rosa_cache_validate
	umask 077
	rosa_auth_prepare_token_dir
	rosa_auth_write_kubeconfig B
	local payload
	payload="$(rosa_cache_get)"
	rosa_cache_unpack "${payload}"
	rosa_cache_remember_fp
	printf 'rosa-auth: prepared mode=B kubeconfig=%s token_dir=%s\n' \
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

cmd_persist() {
	rosa_auth_require_cmds aws tar gzip base64
	rosa_cache_validate
	if [[ "${1:-}" != force ]] && rosa_cache_fp_unchanged; then
		printf 'rosa-auth: token fingerprint unchanged; skip persist\n' >&2
		return 0
	fi
	if rosa_cache_put; then
		:
	else
		return $?
	fi
	rosa_cache_remember_fp
	printf 'rosa-auth: persisted oidc-login state to Secrets Manager\n'
}

cmd_seed() {
	rosa_auth_require_env ENTRA_TENANT_ID ENTRA_PUBLIC_CLIENT_ID ROSA_API_ENDPOINT ROSA_CLUSTER_CA_B64
	rosa_auth_require_cmds oc kubectl timeout aws tar gzip base64
	rosa_cache_validate
	umask 077
	rosa_auth_wipe_token_dir
	rosa_auth_prepare_token_dir
	rosa_auth_write_kubeconfig B
	printf 'rosa-auth: starting bounded device-code seed; use the printed URL on a trusted browser\n' >&2
	rosa_auth_bounded_oc auth whoami
	cmd_persist force
	printf 'rosa-auth: seed stored; delete any seed Pod and retain no local token directory\n' >&2
}

cmd_cleanup() {
	rosa_auth_wipe_token_dir
	rm -f "$(rosa_cache_fp_path)"
	printf 'rosa-auth: removed job-local oidc-login state\n'
}

cmd_status() {
	printf 'mode=B\n'
	printf 'kubeconfig=%s\n' "$(rosa_auth_kubeconfig_path)"
	printf 'token_dir=%s\n' "$(rosa_auth_token_dir)"
	printf 'aws_caller=%s\n' "$(rosa_cache_aws_principal)"
}

maybe_persist_after() {
	if [[ "${ROSA_B_PERSIST:-auto}" == auto ]]; then
		if ! cmd_persist; then
			printf 'rosa-auth: warning: ROSA operation succeeded but automatic cache persistence failed\n' >&2
		fi
	fi
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
	whoami)
		cmd_whoami
		maybe_persist_after
		;;
	run)
		cmd_run "$@"
		maybe_persist_after
		;;
	seed) cmd_seed ;;
	persist) cmd_persist "$@" ;;
	status) cmd_status ;;
	cleanup) cmd_cleanup ;;
	*)
		usage >&2
		return 64
		;;
	esac
}

main "$@"
