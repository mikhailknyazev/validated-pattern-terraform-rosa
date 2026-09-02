#!/usr/bin/env bash
# Purpose: Preview or explicitly apply exact orphaned ROSA subnet-tag deletion.
# What this is not: This runner does not discover subnets or bypass a present-cluster result.
# Prerequisites: Python 3, AWS CLI credentials, explicit subnet ids, and OCM evidence or per-id assertions.
# Authoritative references: https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-tags.html

set -euo pipefail

# Covers: env:SCRIPT_DIR, env:TOOL
# Does: Resolves the repository-relative tool and permits one explicit installed-path override.
# Why: Both manual runners call the same reviewed implementation from any working directory.
# Change: BYO_SUBNET_TAG_TOOL may point at the reviewed installed copy when this example is moved.
# Trap: An absent or unreviewed override fails at execution instead of selecting a different cleaner.
# Evidence: Syntax-only: Bash resolves BASH_SOURCE before constructing the reviewed argv array.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="${BYO_SUBNET_TAG_TOOL:-$SCRIPT_DIR/../../../scripts/operations/byo-subnet-tags.py}"

# Covers: env:AWS_REGION, env:SUBNET_IDS, env:OCM_TOKEN_FILE, env:ASSUME_ABSENT_IDS, env:APPLY_CHANGES, env:SNAPSHOT_DIR, env:REPORT_JSON
# Does: Defines the exact read scope, optional owning-API credential, per-id assertions, approval state, and artifacts.
# Why: Dry-run is the default and every evidence gap must be filled by an explicit cluster-id assertion.
# Change: APPLY_CHANGES=true enables an interactive mutation; assertions affect only the exact ids supplied.
# Trap: The token value belongs only in the owner-only file, never in this environment or command line.
# Evidence: https://api.openshift.com/api/clusters_mgmt/v1/openapi
: "${AWS_REGION:?Set AWS_REGION}"
: "${SUBNET_IDS:?Set SUBNET_IDS to explicit subnet ids separated by spaces}"
OCM_TOKEN_FILE="${OCM_TOKEN_FILE:-}"
ASSUME_ABSENT_IDS="${ASSUME_ABSENT_IDS:-}"
APPLY_CHANGES="${APPLY_CHANGES:-false}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-./artifacts/snapshots}"
REPORT_JSON="${REPORT_JSON:-./artifacts/byo-subnet-tags-clean.json}"

if [[ -z "$OCM_TOKEN_FILE" && -z "$ASSUME_ABSENT_IDS" ]]; then
	echo "Set OCM_TOKEN_FILE or name each evidence gap in ASSUME_ABSENT_IDS" >&2
	exit 2
fi

read -r -a subnet_ids <<<"$SUBNET_IDS"
read -r -a assumed_ids <<<"$ASSUME_ABSENT_IDS"

# Covers: clean, --region, --subnet-id, --ocm-token-file, --assume-absent, --snapshot-dir, --report-json
# Does: Constructs a dry-run command over exact identifiers and owner-only evidence destinations.
# Why: The report must distinguish proved absence from an operator assertion before approval is requested.
# Change: Add assumptions individually; omitting APPLY_CHANGES leaves this command non-mutating.
# Trap: There is no force or global skip; a present owning-API result always refuses an assertion.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-tags.html
command=(python3 "$TOOL" clean --region "$AWS_REGION" --snapshot-dir "$SNAPSHOT_DIR" --report-json "$REPORT_JSON")
for subnet_id in "${subnet_ids[@]}"; do
	command+=(--subnet-id "$subnet_id")
done
if [[ -n "$OCM_TOKEN_FILE" ]]; then
	command+=(--ocm-token-file "$OCM_TOKEN_FILE")
fi
for cluster_id in "${assumed_ids[@]}"; do
	command+=(--assume-absent "$cluster_id")
done

if [[ "$APPLY_CHANGES" == "true" ]]; then
	# Covers: --apply
	# Does: Enables exact-key deletion after the tool's interactive phrase confirmation.
	# Why: A visible environment edit plus a typed confirmation separates inspection from mutation.
	# Change: Leave false or unset for a dry-run; this manual runner never supplies --yes.
	# Trap: Approval does not override present or unobserved cluster states.
	# Evidence: Syntax-only: argparse boolean switch consumed by the bundled tool.
	command+=(--apply)
elif [[ "$APPLY_CHANGES" != "false" ]]; then
	echo "APPLY_CHANGES must be true or false" >&2
	exit 2
fi

"${command[@]}"
