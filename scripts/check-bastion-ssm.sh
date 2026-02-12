#!/bin/bash
# Check bastion instance SSM connection status and logs
# Usage: ./scripts/check-bastion-ssm.sh <instance-id> [region]

set -euo pipefail

INSTANCE_ID="${1:-}"
REGION="${2:-us-east-2}"

if [ -z "$INSTANCE_ID" ]; then
	echo "Error: Instance ID required" >&2
	echo "Usage: $0 <instance-id> [region]" >&2
	exit 1
fi

echo "=== Checking Bastion Instance: $INSTANCE_ID ==="
echo "Region: $REGION"
echo ""

# 1. Instance Status
echo "=== Instance Status ==="
aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
	--query 'Reservations[0].Instances[0].[State.Name,LaunchTime,IamInstanceProfile.Arn,SubnetId,PrivateIpAddress]' \
	--output table
echo ""

# 2. SSM Registration
echo "=== SSM Registration Status ==="
SSM_INFO=$(aws ssm describe-instance-information \
	--filters "Key=InstanceIds,Values=$INSTANCE_ID" \
	--region "$REGION" \
	--output json 2>&1)

if echo "$SSM_INFO" | jq -e '.InstanceInformationList | length > 0' >/dev/null 2>&1; then
	echo "$SSM_INFO" | jq -r '.InstanceInformationList[0] | "Instance ID: \(.InstanceId)\nPing Status: \(.PingStatus)\nLast Ping: \(.LastPingDateTime)\nPlatform: \(.PlatformType) \(.PlatformVersion)"'
else
	echo "ERROR: Instance not registered with SSM"
	echo "Raw output: $SSM_INFO"
fi
echo ""

# 3. IAM Role Check
echo "=== IAM Role Check ==="
INSTANCE_PROFILE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
	--query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text)

if [ -n "$INSTANCE_PROFILE" ] && [ "$INSTANCE_PROFILE" != "None" ]; then
	echo "Instance Profile: $INSTANCE_PROFILE"
	PROFILE_NAME=$(basename "$INSTANCE_PROFILE")
	ROLE_NAME=$(aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" \
		--query 'InstanceProfile.Roles[0].RoleName' --output text)
	echo "Role Name: $ROLE_NAME"
	echo ""
	echo "Attached Policies:"
	aws iam list-attached-role-policies --role-name "$ROLE_NAME" --output table
else
	echo "ERROR: No IAM instance profile attached!"
fi
echo ""

# 4. Console Output (user_data execution)
echo "=== Instance Console Output (User Data Execution) ==="
CONSOLE_OUTPUT=$(aws ec2 get-console-output --instance-id "$INSTANCE_ID" --region "$REGION" \
	--query 'Output' --output text 2>&1)

if [ -n "$CONSOLE_OUTPUT" ]; then
	echo "Last 100 lines of console output:"
	echo "$CONSOLE_OUTPUT" | tail -100
else
	echo "No console output available yet (instance may still be initializing)"
fi
echo ""

# 5. VPC Endpoints Check
echo "=== SSM VPC Endpoints Check ==="
VPC_ID=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
	--query 'Reservations[0].Instances[0].VpcId' --output text)

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
	echo "VPC ID: $VPC_ID"
	echo ""
	echo "SSM-related VPC Endpoints:"
	aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
		--query "VpcEndpoints[?contains(ServiceName, 'ssm') || contains(ServiceName, 'ec2messages') || contains(ServiceName, 'ssmmessages')].[VpcEndpointId,ServiceName,State]" \
		--region "$REGION" --output table
else
	echo "Could not determine VPC ID"
fi
echo ""

# 6. CloudWatch Logs (if available)
echo "=== CloudWatch Logs (SSM Agent) ==="
LOG_GROUP="/aws/ssm/amazon-ssm-agent"
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$REGION" \
	--query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
	echo "Checking logs for instance $INSTANCE_ID..."
	aws logs filter-log-events \
		--log-group-name "$LOG_GROUP" \
		--filter-pattern "$INSTANCE_ID" \
		--region "$REGION" \
		--max-items 20 \
		--query 'events[*].[timestamp,message]' \
		--output table 2>&1 | head -30 || echo "No logs found or log group not accessible"
else
	echo "Log group $LOG_GROUP not found or not accessible"
fi
echo ""

# 7. Summary and Recommendations
echo "=== Summary ==="
if echo "$SSM_INFO" | jq -e '.InstanceInformationList | length > 0' >/dev/null 2>&1; then
	PING_STATUS=$(echo "$SSM_INFO" | jq -r '.InstanceInformationList[0].PingStatus')
	if [ "$PING_STATUS" = "Online" ]; then
		echo "✓ SSM agent is online - you should be able to connect"
		echo ""
		echo "Try connecting:"
		echo "  aws ssm start-session --target $INSTANCE_ID --region $REGION"
	else
		echo "⚠ SSM agent status: $PING_STATUS"
		echo "  Instance is registered but agent may not be fully ready"
		echo "  Wait a few minutes and try again"
	fi
else
	echo "✗ Instance not registered with SSM"
	echo ""
	echo "Possible causes:"
	echo "  1. SSM agent not installed or not running"
	echo "  2. IAM role missing or incorrect permissions"
	echo "  3. SSM VPC endpoints not configured (for private subnets)"
	echo "  4. Instance still initializing (check console output above)"
	echo ""
	echo "Check the console output above for user_data script errors"
fi
