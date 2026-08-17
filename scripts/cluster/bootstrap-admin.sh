#!/usr/bin/env bash
# Manage short-lived Terraform bootstrap HTPasswd admin (#29).
#
# Usage:
#   bootstrap-admin.sh <cluster-name> create      # applies IDP; prints export lines on stdout for eval
#   bootstrap-admin.sh <cluster-name> destroy
#   bootstrap-admin.sh <cluster-name> export-env  # for TF-generated password (module used without script)
#
# create generates a password, passes it into terraform via TF_VAR_bootstrap_admin_password,
# and prints BOOTSTRAP_* exports from that value (no terraform output round-trip).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../common.sh"

CLUSTER_NAME="${1:-}"
ACTION="${2:-}"
BOOTSTRAP_USERNAME_DEFAULT="bootstrap"

if [[ -z "$CLUSTER_NAME" || -z "$ACTION" ]]; then
	error "Usage: $0 <cluster-name> create|destroy|export-env"
	exit 1
fi

CLUSTER_DIR=$(get_cluster_dir "$CLUSTER_NAME")
use_cluster_tf_data_dir "$CLUSTER_NAME"
TERRAFORM_DIR=$(get_terraform_dir infrastructure)
TFVARS="$CLUSTER_DIR/terraform.tfvars"

if [[ ! -f "$TFVARS" ]]; then
	error "terraform.tfvars not found: $TFVARS"
	exit 1
fi

get_cluster_id() {
	local id
	id=$(
		cd "$TERRAFORM_DIR"
		terraform output -no-color -raw cluster_id 2>/dev/null | tr -d '\n\r' || true
	)
	if [[ -z "$id" || "$id" == "null" ]]; then
		error "cluster_id output missing. Run terraform apply for ${CLUSTER_NAME} first."
		exit 1
	fi
	printf '%s' "$id"
}

get_api_url() {
	local url
	url=$(
		cd "$TERRAFORM_DIR"
		terraform output -no-color -raw api_url 2>/dev/null | tr -d '\n\r' || true
	)
	if [[ -z "$url" || "$url" == "null" ]]; then
		error "api_url output missing. Run terraform apply for ${CLUSTER_NAME} first."
		exit 1
	fi
	printf '%s' "$url"
}

# ROSA HTPasswd: 14+ chars, upper, lower, digit, symbol. Avoid shell-hostile quotes.
generate_password() {
	python3 -c '
import secrets, string
alphabet = string.ascii_letters + string.digits + "@%*_-&"
while True:
    p = "".join(secrets.choice(alphabet) for _ in range(20))
    if (any(c.isupper() for c in p) and any(c.islower() for c in p)
            and any(c.isdigit() for c in p) and any(c in "@%*_-&" for c in p)):
        print(p)
        break
'
}

print_exports() {
	local user="$1"
	local pass="$2"
	local api="$3"
	printf "export BOOTSTRAP_USERNAME='%s'\n" "${user//\'/\'\\\'\'}"
	printf "export BOOTSTRAP_PASSWORD='%s'\n" "${pass//\'/\'\\\'\'}"
	printf "export CLUSTER_API_URL='%s'\n" "${api//\'/\'\\\'\'}"
}

run_targeted_apply() {
	local enabled="$1"
	local password="${2:-}"
	local cluster_id
	local log
	cluster_id=$(get_cluster_id)
	log="$(mktemp -t bootstrap-admin.XXXXXX)"
	info "terraform apply -target=module.bootstrap_admin enable_bootstrap_admin_user=${enabled} bootstrap_admin_cluster_id=${cluster_id}"
	# Quiet by default: full terraform output buries real GitOps errors on teardown.
	if (
		cd "$TERRAFORM_DIR"
		# Password via TF_VAR so it is not on the process argv; unset when empty (destroy).
		export TF_VAR_bootstrap_admin_cluster_id="${cluster_id}"
		if [[ -n "$password" ]]; then
			export TF_VAR_bootstrap_admin_password="${password}"
		else
			unset TF_VAR_bootstrap_admin_password 2>/dev/null || true
		fi
		terraform apply -auto-approve -input=false -compact-warnings \
			-var="cluster_config_dir=${CLUSTER_NAME}" \
			-var-file="$TFVARS" \
			-var="enable_bootstrap_admin_user=${enabled}" \
			-target=module.bootstrap_admin
	) >"$log" 2>&1; then
		grep -E '^(Apply complete!|No changes\.|Plan:)' "$log" >&2 || true
		rm -f "$log"
	else
		error "terraform apply -target=module.bootstrap_admin failed (enable=${enabled}). Last 80 lines:"
		tail -80 "$log" >&2 || true
		rm -f "$log"
		exit 1
	fi
}

case "$ACTION" in
create)
	pass=$(generate_password)
	user="${BOOTSTRAP_USERNAME_DEFAULT}"
	api=$(get_api_url)
	run_targeted_apply true "${pass}"
	info "Bootstrap admin created (username=${user})."
	# stdout for eval by Make — password never read back from terraform
	print_exports "${user}" "${pass}" "${api}"
	;;
destroy)
	run_targeted_apply false
	info "Bootstrap admin destroyed (enable_bootstrap_admin_user=false)."
	;;
export-env)
	# For callers that let the module generate the password (no script-supplied value).
	(
		cd "$TERRAFORM_DIR"
		user=$(terraform output -no-color -raw bootstrap_admin_username 2>/dev/null | tr -d '\n\r' || true)
		pass=$(terraform output -no-color -raw bootstrap_admin_password 2>/dev/null | tr -d '\n\r' || true)
		api=$(terraform output -no-color -raw api_url 2>/dev/null | tr -d '\n\r' || true)
		if [[ -z "$user" || "$user" == "null" ]]; then
			user="${BOOTSTRAP_USERNAME_DEFAULT}"
		fi
		if [[ -z "$pass" || "$pass" == "null" ]]; then
			pass=$(terraform state show -json 'module.bootstrap_admin.random_password.bootstrap[0]' 2>/dev/null |
				python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("values",{}).get("result") or "")' 2>/dev/null || true)
		fi
		if [[ -z "$pass" || "$pass" == "null" || -z "$api" || "$api" == "null" ]]; then
			error "bootstrap admin outputs missing. Run create with a password, or apply module.bootstrap_admin with enable=true."
			exit 1
		fi
		print_exports "${user}" "${pass}" "${api}"
	)
	;;
*)
	error "Unknown action: ${ACTION} (expected create|destroy|export-env)"
	exit 1
	;;
esac
