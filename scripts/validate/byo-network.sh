#!/usr/bin/env bash
# VPC validation for ROSA HCP deployments (BYO and post-Terraform network).
# Adapted from reference/ROSAHcpZeroEgressPrerequisites/scripts/validate-rosa-vpc.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
VPC_ID=""
CLUSTER_NAME=""
MIN_PRIVATE_SUBNETS=3
ZERO_EGRESS=false
MULTI_AZ=true
REQUIRE_CLOUDWATCH=false
# Purpose: Add an opt-in, read-only subnet user-tag capacity check.
# What this is not: This block does not discover or delete cluster ownership tags.
# Prerequisites: Python 3 and scripts/operations/byo-subnet-tags.py in this checkout.
# Authoritative references: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html#tag-restrictions
# Covers: env:CHECK_SUBNET_TAG_CAPACITY
# Does: Tracks whether the caller selected the delegated capacity report.
# Why: False preserves the existing validation path until a caller opts into the additional reads.
# Change: Only --check-subnet-tag-capacity changes this value during argument parsing.
# Trap: This flag must never select the clean verb or any EC2 mutation.
# Evidence: Syntax-only: Bash boolean sentinel consumed below in the same script.
CHECK_SUBNET_TAG_CAPACITY=false
REQUIRED_ENDPOINT_SUFFIXES=("s3" "sts" "ecr.api" "ecr.dkr")
OPTIONAL_ENDPOINT_SUFFIXES=("logs" "monitoring")

while [[ $# -gt 0 ]]; do
	case "$1" in
	--vpc-id)
		VPC_ID="$2"
		shift 2
		;;
	--region)
		REGION="$2"
		shift 2
		;;
	--cluster-name)
		CLUSTER_NAME="$2"
		shift 2
		;;
	--zero-egress)
		ZERO_EGRESS=true
		shift
		;;
	--multi-az)
		MULTI_AZ=true
		shift
		;;
	--single-az)
		MULTI_AZ=false
		MIN_PRIVATE_SUBNETS=1
		shift
		;;
	--require-cloudwatch)
		REQUIRE_CLOUDWATCH=true
		shift
		;;
		# Covers: --check-subnet-tag-capacity, env:CHECK_SUBNET_TAG_CAPACITY
		# Does: Delegates capacity accounting for the validated private subnets to the read-only check verb.
		# Why: Pre-create validation is the natural point to detect exhausted EC2 user-tag slots.
		# Change: Omitting the flag leaves the existing network validation path unchanged.
		# Trap: The caller enumerates subnets here; the lifecycle tool never broadens scope by discovering them.
		# Evidence: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html#tag-restrictions
	--check-subnet-tag-capacity)
		CHECK_SUBNET_TAG_CAPACITY=true
		shift
		;;
	-h | --help)
		echo "Usage: $0 [--vpc-id VPC_ID] [--region REGION] [--cluster-name NAME]"
		echo "       [--zero-egress] [--multi-az|--single-az] [--require-cloudwatch]"
		echo "       [--check-subnet-tag-capacity]"
		exit 0
		;;
	*)
		echo "Unknown option: $1"
		exit 1
		;;
	esac
done

export AWS_DEFAULT_REGION="$REGION"

if [[ "$MULTI_AZ" == "false" ]]; then
	MIN_PRIVATE_SUBNETS=1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  ROSA HCP — VPC Validation                                  ║"
printf "║  Region: %-52s ║\n" "$REGION"
echo "╚═══════════════════════════════════════════════════════════════╝"

header "VPC DISCOVERY"
if [[ -n "$VPC_ID" ]]; then
	info "VPC provided via --vpc-id: $VPC_ID"
else
	info "No --vpc-id specified — attempting auto-detection..."
	CANDIDATE_VPCS=()
	if [[ -n "$CLUSTER_NAME" ]]; then
		while IFS= read -r line; do
			[[ -n "$line" ]] && CANDIDATE_VPCS+=("$line")
		done < <(aws ec2 describe-vpcs \
			--filters "Name=tag:Name,Values=*${CLUSTER_NAME}*" \
			--query "Vpcs[*].[VpcId,CidrBlock,Tags[?Key==\`Name\`].Value|[0]]" \
			--output json 2>/dev/null | jq -r '.[] | "\(.[0]) \(.[1]) \(.[2] // "unnamed")"')
	fi
	if [[ ${#CANDIDATE_VPCS[@]} -eq 0 ]]; then
		while IFS= read -r line; do
			[[ -n "$line" ]] && CANDIDATE_VPCS+=("$line")
		done < <(aws ec2 describe-subnets \
			--filters "Name=tag-key,Values=kubernetes.io/role/internal-elb" \
			--query 'Subnets[*].VpcId' --output json 2>/dev/null | jq -r 'unique[]' | while read -r vid; do
			aws ec2 describe-vpcs --vpc-ids "$vid" \
				--query "Vpcs[0].[VpcId,CidrBlock,Tags[?Key==\`Name\`].Value|[0]]" \
				--output json 2>/dev/null | jq -r '"\(.[0]) \(.[1]) \(.[2] // "unnamed")"'
		done)
	fi
	if [[ ${#CANDIDATE_VPCS[@]} -eq 0 ]]; then
		fail "No VPC found. Specify --vpc-id or --cluster-name."
		exit_with_summary "VPC VALIDATION SUMMARY"
	fi
	if [[ ${#CANDIDATE_VPCS[@]} -eq 1 ]]; then
		VPC_ID=$(echo "${CANDIDATE_VPCS[0]}" | awk '{print $1}')
		pass "Auto-detected VPC: $VPC_ID"
	else
		fail "Multiple VPCs found — specify --vpc-id"
		for entry in "${CANDIDATE_VPCS[@]}"; do
			info "  $entry"
		done
		exit_with_summary "VPC VALIDATION SUMMARY"
	fi
fi

header "VPC CONFIGURATION"
VPC_INFO=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --output json 2>&1) || true
if ! echo "$VPC_INFO" | jq -e '.Vpcs[0]' &>/dev/null; then
	fail "VPC $VPC_ID not found in $REGION"
	exit_with_summary "VPC VALIDATION SUMMARY"
fi

VPC_CIDR=$(echo "$VPC_INFO" | jq -r '.Vpcs[0].CidrBlock')
pass "VPC $VPC_ID — CIDR: $VPC_CIDR"

CIDR_PREFIX=$(echo "$VPC_CIDR" | cut -d/ -f2)
if [[ "$CIDR_PREFIX" -le 23 ]]; then
	pass "VPC CIDR /$CIDR_PREFIX meets recommended /23 minimum"
elif [[ "$CIDR_PREFIX" -le 25 ]]; then
	warn "VPC CIDR /$CIDR_PREFIX is smaller than recommended /23"
else
	fail "VPC CIDR /$CIDR_PREFIX is too small"
fi

DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsHostnames \
	--output json 2>/dev/null | jq -r '.EnableDnsHostnames.Value // false')
DNS_SUPPORT=$(aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsSupport \
	--output json 2>/dev/null | jq -r '.EnableDnsSupport.Value // false')

if [[ "$DNS_HOSTNAMES" == "true" ]]; then pass "VPC DNS Hostnames: enabled"; else fail "VPC DNS Hostnames: disabled"; fi
if [[ "$DNS_SUPPORT" == "true" ]]; then pass "VPC DNS Support: enabled"; else fail "VPC DNS Support: disabled"; fi

header "PRIVATE SUBNETS"
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
	--filters "Name=vpc-id,Values=$VPC_ID" \
	--query "Subnets[?MapPublicIpOnLaunch==\`false\`]" --output json 2>/dev/null || echo "[]")
PRIVATE_COUNT=$(echo "$PRIVATE_SUBNETS" | jq 'length')

if [[ "$PRIVATE_COUNT" -ge "$MIN_PRIVATE_SUBNETS" ]]; then
	pass "Private subnets: $PRIVATE_COUNT (minimum: $MIN_PRIVATE_SUBNETS)"
else
	fail "Private subnets: $PRIVATE_COUNT — need at least $MIN_PRIVATE_SUBNETS"
fi

if [[ "$CHECK_SUBNET_TAG_CAPACITY" == "true" ]]; then
	tag_capacity_subnet_ids=()
	while IFS= read -r subnet_id; do
		[[ -n "$subnet_id" ]] && tag_capacity_subnet_ids+=("$subnet_id")
	done < <(echo "$PRIVATE_SUBNETS" | jq -r '.[].SubnetId')
	if [[ ${#tag_capacity_subnet_ids[@]} -eq 0 ]]; then
		fail "Subnet tag capacity: no private subnets were found to check"
	else
		# Covers: env:TAG_TOOL, --region, --subnet-id
		# Does: Runs one read-only implementation against the exact private-subnet ids this validator already read.
		# Why: Delegation prevents capacity arithmetic from diverging between validation and housekeeping.
		# Change: Removing an id narrows the check; adding one checks that explicit subnet without VPC discovery.
		# Trap: A failed or unreadable check is reported as a validation failure, never as free capacity.
		# Evidence: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-subnets.html
		TAG_TOOL=(python3 "$SCRIPT_DIR/../operations/byo-subnet-tags.py" check --region "$REGION")
		for subnet_id in "${tag_capacity_subnet_ids[@]}"; do
			TAG_TOOL+=(--subnet-id "$subnet_id")
		done
		if "${TAG_TOOL[@]}"; then
			pass "Subnet tag capacity: all private subnets have free user-tag slots"
		else
			fail "Subnet tag capacity: check reported a full subnet or unreadable tags"
		fi
	fi
fi

AZ_COUNT=$(echo "$PRIVATE_SUBNETS" | jq '[.[].AvailabilityZone] | unique | length')
if [[ "$MULTI_AZ" == "true" && "$AZ_COUNT" -ge 3 ]]; then
	pass "Private subnets span $AZ_COUNT availability zones"
elif [[ "$MULTI_AZ" == "true" ]]; then
	warn "Private subnets span only $AZ_COUNT AZ(s) — 3 recommended for multi-AZ"
fi

header "SUBNET TAGS"
TAGGED_COUNT=$(aws ec2 describe-subnets \
	--filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
	--query 'length(Subnets)' --output text 2>/dev/null || echo "0")
if [[ "$TAGGED_COUNT" -ge "$MIN_PRIVATE_SUBNETS" ]]; then
	pass "kubernetes.io/role/internal-elb=1 on $TAGGED_COUNT subnet(s)"
else
	fail "kubernetes.io/role/internal-elb=1 missing on required subnets"
fi

header "VPC ENDPOINTS"
ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
	--filters "Name=vpc-id,Values=$VPC_ID" \
	--query 'VpcEndpoints[*].{Service:ServiceName,Type:VpcEndpointType,State:State,PrivateDns:PrivateDnsEnabled}' \
	--output json 2>/dev/null || echo "[]")

for svc in "${REQUIRED_ENDPOINT_SUFFIXES[@]}"; do
	FULL_SVC="com.amazonaws.${REGION}.${svc}"
	MATCH=$(echo "$ENDPOINTS" | jq -r --arg s "$FULL_SVC" '.[] | select(.Service == $s)')
	if [[ -n "$MATCH" ]]; then
		STATE=$(echo "$MATCH" | jq -r '.State')
		TYPE=$(echo "$MATCH" | jq -r '.Type')
		if [[ "$STATE" == "available" ]]; then
			pass "$svc ($TYPE): available"
		else
			fail "$svc ($TYPE): state is '$STATE'"
		fi
		if [[ "$TYPE" == "Interface" ]]; then
			PDNS=$(echo "$MATCH" | jq -r '.PrivateDns // "false"')
			if [[ "$PDNS" == "true" ]]; then pass "$svc: PrivateDnsEnabled=true"; else fail "$svc: PrivateDnsEnabled must be true"; fi
		fi
	else
		if [[ "$ZERO_EGRESS" == "true" ]]; then
			fail "$svc endpoint: NOT FOUND — required for zero egress"
		else
			warn "$svc endpoint: not found — recommended even with NAT"
		fi
	fi
done

for svc in "${OPTIONAL_ENDPOINT_SUFFIXES[@]}"; do
	FULL_SVC="com.amazonaws.${REGION}.${svc}"
	MATCH=$(echo "$ENDPOINTS" | jq -r --arg s "$FULL_SVC" '.[] | select(.Service == $s)')
	if [[ -n "$MATCH" ]]; then
		info "$svc endpoint: present (optional)"
	elif [[ "$REQUIRE_CLOUDWATCH" == "true" ]]; then
		fail "$svc endpoint: required for CloudWatch log forwarding but not found"
	fi
done

header "ENDPOINT SECURITY GROUPS"
SG_IDS=$(aws ec2 describe-vpc-endpoints \
	--filters "Name=vpc-id,Values=$VPC_ID" "Name=vpc-endpoint-type,Values=Interface" \
	--query 'VpcEndpoints[*].Groups[*].GroupId' --output json 2>/dev/null | jq -r '.[][]' | sort -u)
if [[ -z "$SG_IDS" ]]; then
	info "No interface endpoint security groups to check"
else
	for sg in $SG_IDS; do
		ALLOWS_443=$(aws ec2 describe-security-groups --group-ids "$sg" \
			--query "SecurityGroups[0].IpPermissions[?ToPort==\`443\` && FromPort==\`443\`]" \
			--output json 2>/dev/null || echo "[]")
		if [[ $(echo "$ALLOWS_443" | jq 'length') -gt 0 ]]; then
			pass "Security group $sg: allows HTTPS (443) inbound"
		else
			fail "Security group $sg: no HTTPS (443) inbound rule"
		fi
	done
fi

header "ROUTE TABLES"
while read -r sid; do
	[[ -z "$sid" ]] && continue
	RTB=$(aws ec2 describe-route-tables \
		--filters "Name=association.subnet-id,Values=$sid" \
		--query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || echo "None")
	if [[ "$RTB" != "None" ]]; then
		HAS_IGW=$(aws ec2 describe-route-tables --route-table-ids "$RTB" \
			--query "RouteTables[0].Routes[?GatewayId!=null && starts_with(GatewayId, 'igw-')]" \
			--output json 2>/dev/null || echo "[]")
		HAS_NAT=$(aws ec2 describe-route-tables --route-table-ids "$RTB" \
			--query "RouteTables[0].Routes[?NatGatewayId!=null]" \
			--output json 2>/dev/null || echo "[]")
		if [[ $(echo "$HAS_IGW" | jq 'length') -eq 0 ]]; then
			pass "Subnet $sid: no IGW route"
		else
			fail "Subnet $sid: has IGW route on private subnet"
		fi
		if [[ "$ZERO_EGRESS" == "true" ]]; then
			if [[ $(echo "$HAS_NAT" | jq 'length') -eq 0 ]]; then
				pass "Subnet $sid: no NAT route (correct for zero egress)"
			else
				fail "Subnet $sid: has NAT route — must not exist for zero egress"
			fi
		fi
	fi
done < <(echo "$PRIVATE_SUBNETS" | jq -r '.[].SubnetId')

exit_with_summary "VPC VALIDATION SUMMARY — $VPC_ID"
