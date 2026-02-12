#!/bin/bash
# Start sshuttle VPN tunnel via bastion for egress-zero clusters
# Usage: ./scripts/tunnel-start.sh <infrastructure_directory> <cluster_directory>
#
# This script creates a VPN tunnel using sshuttle that routes all VPC traffic
# through the bastion host, allowing access to private egress-zero clusters.

set -euo pipefail

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

INFRA_DIR="${1:-}"
CLUSTER_DIR="${2:-}"

if [ -z "$INFRA_DIR" ]; then
	echo -e "${YELLOW}Error: Infrastructure directory argument required${NC}" >&2
	echo "Usage: $0 <infrastructure_directory> [cluster_directory]" >&2
	exit 1
fi

if [ ! -d "$INFRA_DIR" ]; then
	echo -e "${YELLOW}Error: Infrastructure directory does not exist: $INFRA_DIR${NC}" >&2
	exit 1
fi

echo -e "${BLUE}Starting sshuttle VPN tunnel via bastion...${NC}"

# Check prerequisites
if ! command -v sshuttle >/dev/null 2>&1; then
	echo -e "${YELLOW}Error: sshuttle not found.${NC}" >&2
	echo -e "${YELLOW}Installation instructions:${NC}" >&2
	echo "  macOS:  brew install sshuttle" >&2
	echo "  Linux:  pip install sshuttle  (or use your package manager)" >&2
	echo "  See:    https://github.com/sshuttle/sshuttle" >&2
	exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
	echo -e "${YELLOW}Error: aws CLI not found. Please install AWS CLI.${NC}" >&2
	exit 1
fi

# Get bastion instance ID
# Change to infrastructure directory
cd "$INFRA_DIR"
BASTION_ID=$(terraform output -no-color -raw bastion_instance_id 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' || echo "")

if [ -z "$BASTION_ID" ] || [ "$BASTION_ID" = "null" ]; then
	echo -e "${YELLOW}Error: Bastion not deployed. Enable bastion with enable_bastion=true${NC}" >&2
	exit 1
fi

echo -e "${BLUE}Bastion ID: $BASTION_ID${NC}"

# Get VPC CIDR block
VPC_CIDR=$(terraform output -no-color -raw vpc_cidr_block 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' ||
	terraform output -no-color -json 2>/dev/null | jq -r '.vpc_cidr_block.value // empty' | tr -d '\n\r' || echo "")

if [ -z "$VPC_CIDR" ]; then
	echo -e "${YELLOW}Error: VPC CIDR not found in terraform outputs${NC}" >&2
	exit 1
fi

echo -e "${BLUE}VPC CIDR: $VPC_CIDR${NC}"

# Get AWS region
REGION=$(terraform output -no-color -raw region 2>/dev/null | tr -d '\n\r' | sed 's/[[:space:]]*$//' ||
	terraform output -no-color -json 2>/dev/null | jq -r '.region.value // empty' | tr -d '\n\r' || echo "")

if [ -z "$REGION" ] && [ -n "$CLUSTER_DIR" ] && [ -d "$CLUSTER_DIR" ]; then
	# Fallback to reading from terraform.tfvars
	REGION=$(grep -E "^region\s*=" "$CLUSTER_DIR/terraform.tfvars" 2>/dev/null |
		cut -d'"' -f2 | cut -d"'" -f2 | head -1 | tr -d '\n\r' || echo "")
fi

if [ -z "$REGION" ]; then
	REGION="us-east-1"
fi

echo -e "${BLUE}AWS Region: $REGION${NC}"

# Check if tunnel is already running
if pgrep -f "sshuttle.*$VPC_CIDR" >/dev/null 2>&1; then
	echo -e "${YELLOW}sshuttle tunnel already running for $VPC_CIDR${NC}"
	exit 0
fi

# Start the tunnel
echo -e "${YELLOW}Note: sshuttle requires sudo privileges. You will be prompted for your local sudo password.${NC}"

PIDFILE="/tmp/sshuttle-egress-zero-$BASTION_ID.pid"

# Build the SSH command with proper ProxyCommand format
# Use sh -c wrapper to properly handle the aws command in ProxyCommand
SSH_CMD="ssh -o ProxyCommand=\"sh -c \\\"aws --region $REGION ssm start-session --target $BASTION_ID --document-name AWS-StartSSHSession --parameters portNumber=22\\\"\" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo -e "${BLUE}Starting sshuttle...${NC}"
echo -e "${BLUE}  Bastion: $BASTION_ID${NC}"
echo -e "${BLUE}  VPC CIDR: $VPC_CIDR${NC}"
echo -e "${BLUE}  Region: $REGION${NC}"

# Verify bastion is available via SSM
echo -e "${BLUE}Verifying bastion is available via SSM...${NC}"

# Check instance state
INSTANCE_STATE=$(aws ec2 describe-instance-status --instance-ids "$BASTION_ID" --region "$REGION" --include-all-instances --query 'InstanceStatuses[0].InstanceState.Name' --output text 2>/dev/null || echo "Unknown")
if [ "$INSTANCE_STATE" != "running" ]; then
	echo -e "${RED}Error: Bastion instance is not running (state: $INSTANCE_STATE).${NC}" >&2
	echo -e "${YELLOW}Check bastion status: aws ec2 describe-instance-status --instance-ids $BASTION_ID --region $REGION${NC}" >&2
	exit 1
fi

echo -e "${GREEN}Bastion instance is running${NC}"

# Check if SSM VPC endpoints exist (for private subnet access)
echo -e "${BLUE}Checking SSM VPC endpoints...${NC}"
SSM_ENDPOINTS=$(terraform output -no-color -json ssm_endpoint_ids 2>/dev/null | jq -r 'if type == "object" then (.ssm // empty) else empty end' 2>/dev/null || echo "")
if [ -n "$SSM_ENDPOINTS" ] && [ "$SSM_ENDPOINTS" != "null" ]; then
	echo -e "${GREEN}SSM VPC endpoints are configured${NC}"
else
	echo -e "${YELLOW}Warning: SSM VPC endpoints not found in terraform outputs.${NC}" >&2
	echo -e "${YELLOW}This may be normal if bastion has a public IP, but SSM access from private subnets requires VPC endpoints.${NC}" >&2
fi

# Check SSM agent status
SSM_STATUS=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$BASTION_ID" --region "$REGION" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "Unknown")

if [ "$SSM_STATUS" = "Online" ]; then
	echo -e "${GREEN}SSM agent is online${NC}"
elif [ "$SSM_STATUS" = "Unknown" ] || [ -z "$SSM_STATUS" ]; then
	echo -e "${RED}Error: SSM agent is not connected (status: $SSM_STATUS).${NC}" >&2
	echo -e "${YELLOW}This usually means:${NC}" >&2
	echo -e "${YELLOW}  1. SSM agent is still initializing (wait 2-5 minutes after instance launch)${NC}" >&2
	echo -e "${YELLOW}  2. SSM VPC endpoints are not configured or not available${NC}" >&2
	echo -e "${YELLOW}  3. Instance IAM role doesn't have SSM permissions${NC}" >&2
	echo "" >&2
	echo -e "${YELLOW}Troubleshooting steps:${NC}" >&2
	echo -e "${YELLOW}  1. Check SSM agent status:${NC}" >&2
	echo -e "${BLUE}     aws ssm describe-instance-information --filters \"Key=InstanceIds,Values=$BASTION_ID\" --region $REGION${NC}" >&2
	echo -e "${YELLOW}  2. Check if SSM VPC endpoints exist:${NC}" >&2
	echo -e "${BLUE}     cd $INFRA_DIR && terraform output -json ssm_endpoint_ids${NC}" >&2
	echo -e "${YELLOW}  3. Verify instance IAM role has SSM permissions (should have AmazonSSMManagedInstanceCore policy)${NC}" >&2
	echo -e "${YELLOW}  4. Wait a few minutes and try again if instance was just created${NC}" >&2
	echo "" >&2
	echo -e "${YELLOW}If SSM endpoints are missing, ensure the bastion module was applied with private_subnet_ids configured.${NC}" >&2
	exit 1
else
	echo -e "${YELLOW}Warning: SSM agent status is '$SSM_STATUS' (expected 'Online').${NC}" >&2
	echo -e "${YELLOW}SSM agent may still be initializing. Attempting to start tunnel anyway...${NC}" >&2
fi

# Run sshuttle and capture output
# Note: We do NOT use --dns flag because:
# 1. The bastion has no internet access (egress-zero), so DNS queries would fail
# 2. DNS resolution for VPC resources should work via VPC DNS (Route53 resolver)
# 3. External DNS queries (AWS APIs, etc.) should use local DNS, not tunnel
echo -e "${BLUE}Starting sshuttle tunnel...${NC}"
# Run sshuttle and capture both stdout and stderr
# Note: sshuttle in daemon mode returns immediately, so we check the PID file later
SSHUTTLE_OUTPUT=$(sudo sshuttle \
	--ssh-cmd "$SSH_CMD" \
	--remote "ec2-user@$BASTION_ID" \
	"$VPC_CIDR" \
	--daemon \
	--pidfile "$PIDFILE" 2>&1)
SSHUTTLE_EXIT=$?

# Always show sshuttle output for debugging
if [ -n "$SSHUTTLE_OUTPUT" ]; then
	echo -e "${BLUE}sshuttle output:${NC}"
	echo "$SSHUTTLE_OUTPUT"
fi

# Check if sshuttle command failed immediately
if [ $SSHUTTLE_EXIT -ne 0 ]; then
	echo -e "${RED}Failed to start tunnel (exit code: $SSHUTTLE_EXIT).${NC}" >&2
	echo -e "${YELLOW}Check:${NC}" >&2
	echo -e "${YELLOW}  1. Bastion status: aws ec2 describe-instance-status --instance-ids $BASTION_ID --region $REGION${NC}" >&2
	echo -e "${YELLOW}  2. AWS credentials: aws sts get-caller-identity${NC}" >&2
	echo -e "${YELLOW}  3. SSM access: aws ssm start-session --target $BASTION_ID --region $REGION${NC}" >&2
	echo -e "${YELLOW}  4. sshuttle installation: command -v sshuttle${NC}" >&2
	echo -e "${YELLOW}Note: sshuttle requires sudo privileges.${NC}" >&2
	exit 1
fi

# Verify tunnel started
sleep 2
if [ -f "$PIDFILE" ]; then
	PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
	# Check if PID from file matches a running sshuttle process
	if [ -n "$PID" ] && pgrep -f "sshuttle.*$VPC_CIDR" | grep -q "^${PID}$" 2>/dev/null; then
		echo -e "${GREEN}sshuttle tunnel started successfully for VPC $VPC_CIDR${NC}"
		echo -e "${GREEN}All traffic to $VPC_CIDR is now routed through the bastion${NC}"
		echo -e "${GREEN}You can now use oc login with the direct API URL${NC}"
		echo -e "${BLUE}Tunnel PID: $PID${NC}"
	elif [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
		# PID is valid but might not match sshuttle pattern - still report success
		echo -e "${GREEN}sshuttle tunnel started successfully for VPC $VPC_CIDR${NC}"
		echo -e "${GREEN}All traffic to $VPC_CIDR is now routed through the bastion${NC}"
		echo -e "${GREEN}You can now use oc login with the direct API URL${NC}"
		echo -e "${BLUE}Tunnel PID: $PID${NC}"
	else
		# PID file exists but process isn't running - check if sshuttle is running anyway
		# This can happen if sshuttle crashes and restarts, or if the PID file is stale
		if pgrep -f "sshuttle.*$VPC_CIDR" >/dev/null 2>&1; then
			ACTUAL_PID=$(pgrep -f "sshuttle.*$VPC_CIDR" | head -1)
			# Only warn if PIDs are different
			if [ "$PID" != "$ACTUAL_PID" ]; then
				echo -e "${YELLOW}Warning: PID file contains stale PID ($PID), but sshuttle is running (PID: $ACTUAL_PID)${NC}" >&2
			fi
			echo -e "${GREEN}sshuttle tunnel is active for VPC $VPC_CIDR${NC}"
			echo -e "${BLUE}Tunnel PID: $ACTUAL_PID${NC}"
			# Update PID file with correct PID (may need sudo if owned by root)
			echo "$ACTUAL_PID" | sudo tee "$PIDFILE" >/dev/null 2>&1 || echo "$ACTUAL_PID" >"$PIDFILE" 2>&1 || true
		else
			echo -e "${RED}Error: Tunnel process not running.${NC}" >&2
			echo -e "${YELLOW}PID file exists but process is not running.${NC}" >&2
			echo -e "${YELLOW}PID file: $PIDFILE${NC}" >&2
			echo -e "${YELLOW}PID in file: $PID${NC}" >&2
			if [ -n "$SSHUTTLE_OUTPUT" ]; then
				echo -e "${YELLOW}sshuttle output:${NC}" >&2
				echo "$SSHUTTLE_OUTPUT" >&2
			fi
			# Clean up stale PID file (may need sudo if owned by root)
			sudo rm -f "$PIDFILE" 2>/dev/null || rm -f "$PIDFILE" 2>/dev/null || true
			exit 1
		fi
	fi
else
	# PID file doesn't exist - check if sshuttle is running anyway
	if pgrep -f "sshuttle.*$VPC_CIDR" >/dev/null 2>&1; then
		ACTUAL_PID=$(pgrep -f "sshuttle.*$VPC_CIDR" | head -1)
		echo -e "${YELLOW}Warning: PID file not found, but sshuttle is running (PID: $ACTUAL_PID)${NC}" >&2
		echo -e "${GREEN}sshuttle tunnel is active for VPC $VPC_CIDR${NC}"
		echo -e "${BLUE}Tunnel PID: $ACTUAL_PID${NC}"
		# Create PID file with correct PID (may need sudo if owned by root)
		echo "$ACTUAL_PID" | sudo tee "$PIDFILE" >/dev/null 2>&1 || echo "$ACTUAL_PID" >"$PIDFILE" 2>&1 || true
	else
		echo -e "${RED}Error: PID file not created and tunnel is not running.${NC}" >&2
		echo -e "${YELLOW}Tunnel may not have started.${NC}" >&2
		if [ -n "$SSHUTTLE_OUTPUT" ]; then
			echo -e "${YELLOW}sshuttle output:${NC}" >&2
			echo "$SSHUTTLE_OUTPUT" >&2
		fi
		exit 1
	fi
fi
