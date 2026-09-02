#!/usr/bin/env bash
# Purpose: Run the read-only BYO subnet tag capacity and ownership-key check.
# What this is not: This runner cannot delete or change any AWS tag.
# Prerequisites: Python 3, AWS CLI credentials, and explicit subnet ids in SUBNET_IDS.
# Authoritative references: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-subnets.html

set -euo pipefail

# Covers: env:SCRIPT_DIR, env:TOOL
# Does: Resolves the repository-relative tool and permits one explicit installed-path override.
# Why: The copied runner works from any current directory without duplicating the Python implementation.
# Change: BYO_SUBNET_TAG_TOOL may point at the reviewed installed copy when this example is moved.
# Trap: An absent or unreviewed override fails at execution instead of falling back to another tool.
# Evidence: Syntax-only: Bash resolves BASH_SOURCE before constructing the reviewed argv array.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="${BYO_SUBNET_TAG_TOOL:-$SCRIPT_DIR/../../../scripts/operations/byo-subnet-tags.py}"

# Covers: env:AWS_REGION, env:SUBNET_IDS, env:REPORT_JSON
# Does: Selects one AWS region, an explicit whitespace-delimited subnet list, and an owner-readable report path.
# Why: Explicit ids keep the blast radius visible; an override supports copying the runner beside an installed tool.
# Change: Changing ids changes only the named read scope; omitting the report path uses the local default.
# Trap: No VPC id is accepted because this tool deliberately has no subnet-discovery mode.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-tags.html
: "${AWS_REGION:?Set AWS_REGION}"
: "${SUBNET_IDS:?Set SUBNET_IDS to explicit subnet ids separated by spaces}"
REPORT_JSON="${REPORT_JSON:-./artifacts/byo-subnet-tags-check.json}"

read -r -a subnet_ids <<<"$SUBNET_IDS"

# Covers: check, --region, --subnet-id, --report-json
# Does: Builds one argv element per subnet and writes a structured report without invoking DeleteTags.
# Why: Arrays preserve exact identifiers without shell re-parsing or wildcard expansion.
# Change: Add or remove a SUBNET_IDS entry to change the read scope; the command has no mutation switch.
# Trap: Do not replace the array with eval or a VPC query; either would hide the effective scope.
# Evidence: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-tags.html
command=(python3 "$TOOL" check --region "$AWS_REGION" --report-json "$REPORT_JSON")
for subnet_id in "${subnet_ids[@]}"; do
	command+=(--subnet-id "$subnet_id")
done
"${command[@]}"
