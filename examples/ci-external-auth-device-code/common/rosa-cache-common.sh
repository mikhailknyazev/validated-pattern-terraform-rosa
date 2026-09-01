#!/usr/bin/env bash
# Purpose: Function library for a Secrets Manager-backed Mode B oidc-login cache.
# What this is not: This file is not an entry point and is not sourced by Mode A.
# Prerequisites: rosa-auth-common.sh already sourced; AWS CLI, tar, gzip and base64 available.
# Authoritative references:
# - https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/get-secret-value.html
# - https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/put-secret-value.html
# Covers: env:AWS_REGION, env:ROSA_B_SECRET_ID, env:ROSA_B_PERSIST, env:ROSA_B_FP_FILE, --region, --secret-id, --query, --output, --secret-string, --decode, --exclude
# Does: Defines Secrets Manager restore, measured-size refusal, owner-only file transfer, fingerprint and caller-observation helpers.
# Why: A separate Mode B-only library keeps refresh-token custody absent from both Mode A distributions.
# Change: Another secret, region or persistence policy selects a different custody boundary or write cadence.
# Trap: A direct payload argument, oversized value or swallowed write error can expose or falsely report persisted authority.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/secretsmanager/put-secret-value.html

rosa_cache_validate() {
	rosa_auth_require_env AWS_REGION ROSA_B_SECRET_ID || return $?
	case "${ROSA_B_PERSIST:-auto}" in
	auto | never) return 0 ;;
	*)
		printf 'rosa-auth: ROSA_B_PERSIST must be auto or never\n' >&2
		return 64
		;;
	esac
}

rosa_cache_b64_encode() {
	if base64 -w0 </dev/null >/dev/null 2>&1; then
		base64 -w0
	else
		base64 | tr -d '\n'
	fi
}

rosa_cache_b64_decode() {
	if base64 -d </dev/null >/dev/null 2>&1; then
		base64 -d
	else
		base64 --decode
	fi
}

rosa_cache_has_files() {
	local directory
	directory="$(rosa_auth_token_dir)"
	[[ -d "${directory}" ]] || return 1
	[[ -n "$(find "${directory}" -type f ! -path '*/lost+found/*' -print -quit 2>/dev/null)" ]]
}

rosa_cache_pack() {
	local directory
	directory="$(rosa_auth_token_dir)"
	if [[ ! -d "${directory}" ]]; then
		printf 'rosa-auth: token directory does not exist: %s\n' "${directory}" >&2
		return 1
	fi
	if ! rosa_cache_has_files; then
		printf 'rosa-auth: token directory is empty; seed first\n' >&2
		return 1
	fi
	# Explicit gzip avoids platform-dependent tar stdout padding while keeping
	# the stored archive portable between GNU tar and bsdtar readers.
	# https://www.gnu.org/software/tar/manual/html_node/gzip.html
	tar -C "${directory}" --exclude=lost+found -cf - . | gzip -c | rosa_cache_b64_encode
}

rosa_cache_unpack() {
	local payload="$1" directory
	directory="$(rosa_auth_token_dir)"
	case "${payload}" in
	'' | None | pending-seed | null)
		printf 'rosa-auth: Mode B secret is empty or pending seed; run seed first\n' >&2
		return 1
		;;
	esac
	rosa_auth_prepare_token_dir
	rosa_auth_wipe_token_dir
	if ! printf '%s' "${payload}" | rosa_cache_b64_decode | tar -C "${directory}" -xzf -; then
		printf 'rosa-auth: Mode B secret is not a token archive; run seed first\n' >&2
		return 1
	fi
	chmod 700 "${directory}" || true
	find "${directory}" -type f -exec chmod 600 {} +
	if ! rosa_cache_has_files; then
		printf 'rosa-auth: unpacked Mode B token archive has no files; run seed first\n' >&2
		return 1
	fi
}

rosa_cache_fingerprint() {
	local directory
	directory="$(rosa_auth_token_dir)"
	if ! rosa_cache_has_files; then
		printf 'empty\n'
		return 0
	fi
	if command -v sha256sum >/dev/null 2>&1; then
		(
			cd "${directory}" || exit 1
			find . -type f ! -path './lost+found/*' -print0 |
				sort -z |
				xargs -0 sha256sum |
				sha256sum |
				awk '{print $1}'
		)
	else
		printf 'unavailable\n'
	fi
}

rosa_cache_fp_path() {
	printf '%s' "${ROSA_B_FP_FILE:-/tmp/rosa-mode-b.fingerprint}"
}

rosa_cache_remember_fp() {
	umask 077
	rosa_cache_fingerprint >"$(rosa_cache_fp_path)"
}

rosa_cache_fp_unchanged() {
	local previous current
	previous="$(cat "$(rosa_cache_fp_path)" 2>/dev/null || true)"
	current="$(rosa_cache_fingerprint)"
	[[ -n "${previous}" && "${previous}" == "${current}" ]]
}

rosa_cache_get() {
	local payload
	payload="$(aws secretsmanager get-secret-value \
		--region "${AWS_REGION}" \
		--secret-id "${ROSA_B_SECRET_ID}" \
		--query SecretString \
		--output text)"
	payload="${payload%$'\n'}"
	if [[ -z "${payload}" || "${payload}" == None ]]; then
		printf 'rosa-auth: Mode B secret is empty; run seed first\n' >&2
		return 1
	fi
	printf '%s' "${payload}"
}

rosa_cache_put() {
	local payload size temporary_file return_code=0
	payload="$(rosa_cache_pack)"
	size="${#payload}"
	if [[ "${size}" -gt 65536 ]]; then
		printf 'rosa-auth: packed token archive is %s bytes; Secrets Manager string limit is 65536\n' "${size}" >&2
		return 1
	fi
	temporary_file="$(mktemp)"
	umask 077
	printf '%s' "${payload}" >"${temporary_file}"
	chmod 600 "${temporary_file}"
	if aws secretsmanager put-secret-value \
		--region "${AWS_REGION}" \
		--secret-id "${ROSA_B_SECRET_ID}" \
		--secret-string "file://${temporary_file}" >/dev/null; then
		return_code=0
	else
		return_code=$?
	fi
	rm -f "${temporary_file}"
	return "${return_code}"
}

rosa_cache_aws_principal() {
	local principal
	if command -v aws >/dev/null 2>&1 &&
		principal="$(aws sts get-caller-identity --output text --query '[Account,Arn]' 2>/dev/null)" &&
		[[ -n "${principal}" ]]; then
		printf '%s' "${principal}"
	else
		printf 'unobserved'
	fi
}
