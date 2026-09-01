#!/usr/bin/env bash
# Purpose: Function library for device-code kubeconfig and bounded ROSA API access.
# What this is not: This file is not an entry point and never selects a CI path or cache backend.
# Prerequisites: Bash 4+, oc, kubectl oidc-login, GNU timeout, and reviewed identity/TLS inputs.
# Authoritative references:
# - https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md
# - https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins
# Covers: env:KUBECONFIG, env:ROSA_KUBECONFIG, env:OIDC_TOKEN_CACHE_DIR, env:ROSA_AUTH_SKIP_KUBECONFIG_WRITE, env:ROSA_AUTH_TIMEOUT_SECONDS, env:ROSA_HOME, --foreground, --oidc-issuer-url, --oidc-client-id, --oidc-extra-scope, --grant-type, --token-cache-storage, --token-cache-dir
# Does: Defines path, permission, YAML-quoting, template-scope and bounded oc helpers shared by all four entry points.
# Why: One function-only library keeps security-sensitive authentication behavior identical without hiding each path's fixed mode.
# Change: Scope, cache-path or timeout changes alter token custody, interaction requirements or the maximum wait.
# Trap: Sourcing a different common generation can pair an entry point with incompatible template or cleanup semantics.
# Evidence: https://github.com/int128/kubelogin/blob/v1.36.2/docs/setup.md

rosa_auth_trace_off() {
	set +x
	set +o xtrace 2>/dev/null || true
}

rosa_auth_require_cmds() {
	local missing=0 command_name
	for command_name in "$@"; do
		if ! command -v "${command_name}" >/dev/null 2>&1; then
			printf 'rosa-auth: required command not found: %s\n' "${command_name}" >&2
			missing=1
		fi
	done
	[[ "${missing}" -eq 0 ]]
}

rosa_auth_require_env() {
	local name
	for name in "$@"; do
		if [[ -z "${!name:-}" ]]; then
			printf 'rosa-auth: required environment variable is empty: %s\n' "${name}" >&2
			return 64
		fi
	done
}

rosa_auth_kubeconfig_path() {
	printf '%s' "${ROSA_KUBECONFIG:-${KUBECONFIG:-/tmp/rosa-exec-kubeconfig}}"
}

rosa_auth_token_dir() {
	printf '%s' "${OIDC_TOKEN_CACHE_DIR:-/tmp/rosa-oidc-cache}"
}

rosa_auth_prepare_token_dir() {
	local directory
	directory="$(rosa_auth_token_dir)"
	mkdir -p "${directory}"
	chmod 700 "${directory}" || true
}

rosa_auth_wipe_token_dir() {
	local directory
	directory="$(rosa_auth_token_dir)"
	mkdir -p "${directory}"
	find "${directory}" -mindepth 1 -maxdepth 1 ! -name lost+found -exec rm -rf {} +
}

rosa_auth_yaml_sq() {
	local value="${1-}"
	value="${value//\'/\'\'}"
	printf "'%s'" "${value}"
}

rosa_auth_assert_template_scope() {
	local mode="$1" destination="$2"
	local scope_pattern='^[[:space:]]*-[[:space:]]*--oidc-extra-scope=offline_access[[:space:]]*$'
	case "${mode}" in
	A)
		if grep -Eq "${scope_pattern}" "${destination}"; then
			printf 'rosa-auth: Mode A kubeconfig must not request offline_access\n' >&2
			return 1
		fi
		;;
	B)
		if ! grep -Eq "${scope_pattern}" "${destination}"; then
			printf 'rosa-auth: Mode B kubeconfig must request offline_access\n' >&2
			return 1
		fi
		;;
	*)
		printf 'rosa-auth: internal mode must be A or B\n' >&2
		return 70
		;;
	esac
}

rosa_auth_write_kubeconfig() {
	local mode="$1" destination issuer token_dir
	destination="$(rosa_auth_kubeconfig_path)"
	if [[ "${ROSA_AUTH_SKIP_KUBECONFIG_WRITE:-0}" == 1 ]]; then
		if [[ ! -s "${destination}" ]]; then
			printf 'rosa-auth: ROSA_AUTH_SKIP_KUBECONFIG_WRITE=1 but %s is missing\n' "${destination}" >&2
			return 1
		fi
		rosa_auth_assert_template_scope "${mode}" "${destination}" || return $?
		export KUBECONFIG="${destination}"
		return 0
	fi

	issuer="https://login.microsoftonline.com/${ENTRA_TENANT_ID}/v2.0"
	token_dir="$(rosa_auth_token_dir)"
	mkdir -p "$(dirname "${destination}")"
	umask 077
	cat >"${destination}" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: rosa
  cluster:
    server: $(rosa_auth_yaml_sq "https://${ROSA_API_ENDPOINT}:443")
    certificate-authority-data: $(rosa_auth_yaml_sq "${ROSA_CLUSTER_CA_B64}")
contexts:
- name: rosa
  context:
    cluster: rosa
    user: entra-device-code
current-context: rosa
users:
- name: entra-device-code
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: kubectl
      args:
      - oidc-login
      - get-token
      # Quote the whole flag=value scalar. Quoting only the value leaves quote
      # bytes inside the argument received by kubelogin.
      # https://yaml.org/spec/1.2.2/#73-flow-scalar-styles
      - $(rosa_auth_yaml_sq "--oidc-issuer-url=${issuer}")
      - $(rosa_auth_yaml_sq "--oidc-client-id=${ENTRA_PUBLIC_CLIENT_ID}")
      - --oidc-extra-scope=profile
EOF

	if [[ "${mode}" == B ]]; then
		cat >>"${destination}" <<'EOF'
      - --oidc-extra-scope=offline_access
EOF
	fi

	cat >>"${destination}" <<EOF
      - --grant-type=device-code
      - --token-cache-storage=disk
      # The same whole-scalar rule applies to filesystem paths.
      # https://yaml.org/spec/1.2.2/#73-flow-scalar-styles
      - $(rosa_auth_yaml_sq "--token-cache-dir=${token_dir}")
      interactiveMode: Never
      provideClusterInfo: false
EOF
	chmod 600 "${destination}" || true
	rosa_auth_assert_template_scope "${mode}" "${destination}" || return $?
	export KUBECONFIG="${destination}"
}

rosa_auth_oc() {
	env KUBECONFIG="$(rosa_auth_kubeconfig_path)" HOME="${ROSA_HOME:-/tmp}" oc "$@"
}

rosa_auth_bounded_oc() {
	local timeout_seconds="${ROSA_AUTH_TIMEOUT_SECONDS:-300}"
	local kubeconfig home
	if [[ ! "${timeout_seconds}" =~ ^[1-9][0-9]*$ ]]; then
		printf 'rosa-auth: ROSA_AUTH_TIMEOUT_SECONDS must be a positive integer\n' >&2
		return 64
	fi
	rosa_auth_require_cmds timeout || return $?
	kubeconfig="$(rosa_auth_kubeconfig_path)"
	home="${ROSA_HOME:-/tmp}"
	if timeout --foreground 1 true >/dev/null 2>&1; then
		timeout --foreground "${timeout_seconds}" env KUBECONFIG="${kubeconfig}" HOME="${home}" oc "$@"
	else
		timeout "${timeout_seconds}" env KUBECONFIG="${kubeconfig}" HOME="${home}" oc "$@"
	fi
}
