#!/usr/bin/env bash
# Shared helpers for prerequisite validation scripts.

# shellcheck disable=SC2034
PASS=0
FAIL=0
WARN=0
INFO=0

pass() {
	PASS=$((PASS + 1))
	printf "  \033[32m✓ PASS\033[0m  %s\n" "$1"
}

fail() {
	FAIL=$((FAIL + 1))
	printf "  \033[31m✗ FAIL\033[0m  %s\n" "$1"
}

warn() {
	WARN=$((WARN + 1))
	printf "  \033[33m⚠ WARN\033[0m  %s\n" "$1"
}

info() {
	INFO=$((INFO + 1))
	printf "  \033[36mℹ INFO\033[0m  %s\n" "$1"
}

header() {
	printf "\n\033[1;37m━━━ %s ━━━\033[0m\n" "$1"
}

print_summary() {
	local title="${1:-VALIDATION SUMMARY}"
	echo ""
	echo "╔═══════════════════════════════════════════════════════════════╗"
	printf "║  \033[1m%s\033[0m\n" "$title"
	echo "╠═══════════════════════════════════════════════════════════════╣"
	printf "║  \033[32m✓ PASS : %-4d\033[0m                                              ║\n" "$PASS"
	printf "║  \033[31m✗ FAIL : %-4d\033[0m                                              ║\n" "$FAIL"
	printf "║  \033[33m⚠ WARN : %-4d\033[0m                                              ║\n" "$WARN"
	printf "║  \033[36mℹ INFO : %-4d\033[0m                                              ║\n" "$INFO"
	echo "╚═══════════════════════════════════════════════════════════════╝"
	echo ""
}

exit_with_summary() {
	local title="${1:-VALIDATION SUMMARY}"
	print_summary "$title"
	if [[ "$FAIL" -eq 0 ]]; then
		printf "\033[32m✓ All checks passed.\033[0m\n"
		exit 0
	fi
	printf "\033[31m✗ %s issue(s) found. Fix FAIL items before proceeding.\033[0m\n" "$FAIL"
	exit 1
}

# Returns 0 if first float >= second float
float_gte() {
	awk -v a="$1" -v b="$2" 'BEGIN { exit (a + 0 >= b + 0) ? 0 : 1 }'
}

# Returns 0 if first semver (major.minor.patch) >= second
semver_gte() {
	local a="$1"
	local b="$2"
	awk -v a="$a" -v b="$b" 'BEGIN {
		split(a, A, ".");
		split(b, B, ".");
		for (i = 1; i <= 3; i++) {
			ai = (A[i] == "" ? 0 : A[i]) + 0;
			bi = (B[i] == "" ? 0 : B[i]) + 0;
			if (ai > bi) exit 0;
			if (ai < bi) exit 1;
		}
		exit 0;
	}'
}

check_tool() {
	local cmd="$1"
	local min_ver="$2"
	local label="$3"
	if command -v "$cmd" &>/dev/null; then
		local ver
		case "$cmd" in
		rosa) ver=$(rosa version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) ;;
		aws) ver=$(aws --version 2>&1 | grep -oE 'aws-cli/[0-9]+\.[0-9]+\.[0-9]+' | cut -d/ -f2) ;;
		oc) ver=$(oc version --client 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) ;;
		terraform) ver=$(terraform --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d v) ;;
		git) ver=$(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+') ;;
		jq) ver=$(jq --version 2>&1 | grep -oE '[0-9]+\.[0-9.]+') ;;
		curl) ver=$(curl --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) ;;
		*) ver="unknown" ;;
		esac
		if [[ -z "${ver:-}" || "$ver" == "unknown" ]]; then
			fail "$label found but version could not be determined (minimum: $min_ver)"
		elif semver_gte "$ver" "$min_ver"; then
			pass "$label found: v${ver} (minimum: $min_ver)"
		else
			fail "$label v${ver} is below minimum v${min_ver}"
		fi
	else
		fail "$label NOT FOUND — install v${min_ver}+"
	fi
}

check_url() {
	local url="$1"
	local label="$2"
	if curl -sf --connect-timeout 5 --max-time 10 -o /dev/null "$url" 2>/dev/null; then
		pass "$label: reachable"
	else
		fail "$label: NOT reachable — check firewall/proxy settings"
	fi
}
