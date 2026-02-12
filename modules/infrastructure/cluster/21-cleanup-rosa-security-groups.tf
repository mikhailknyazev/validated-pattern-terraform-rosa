# Cleanup ROSA-managed security groups on destroy
# Workaround for ROSA bug: ROSA's control plane operator creates security groups with ingress/egress rules
# that ROSA doesn't clean up during cluster deletion. These orphaned rules block security group deletion,
# which blocks VPC deletion, causing terraform destroy to hang.
#
# This null_resource runs a destroy-time provisioner to proactively delete ROSA-managed security groups
# after the cluster is destroyed. It identifies security groups by:
# - ClusterName tag matching cluster name
# - Description "VPC endpoint security group"
#
# Reference: Based on cleanup-rosa-security-groups-workaround.sh script logic
resource "null_resource" "cleanup_rosa_security_groups" {
  count = local.persists_through_sleep ? 1 : 0

  # Store cluster info in triggers for use during destroy
  # Note: We don't reference cluster here to avoid creating a dependency
  # Instead, the cluster resource will depend on this cleanup resource
  # This ensures cleanup runs AFTER cluster is destroyed (reverse dependency order)
  triggers = {
    cluster_name = var.cluster_name
    region       = var.region
  }

  # No-op on create (cluster is being created, no cleanup needed)
  provisioner "local-exec" {
    when    = create
    command = "echo 'Cluster ${var.cluster_name} created - no security group cleanup needed'"
  }

  # Cleanup ROSA-managed security groups on destroy
  # This runs AFTER cluster and all child resources are destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -euo pipefail
      
      CLUSTER_NAME="${self.triggers.cluster_name}"
      REGION="${self.triggers.region}"
      
      echo "Cleaning up ROSA-managed security groups for cluster '$CLUSTER_NAME' in region $REGION..."
      
      # Find security groups matching exact criteria:
      # - ClusterName tag matches cluster name
      # - Description "VPC endpoint security group"
      SG_IDS=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=tag:ClusterName,Values=$CLUSTER_NAME" "Name=description,Values=VPC endpoint security group" \
        --query 'SecurityGroups[*].GroupId' \
        --output text 2>/dev/null || echo "")
      
      if [ -z "$SG_IDS" ]; then
        echo "No ROSA-managed security groups found matching criteria (may already be deleted)"
        exit 0
      fi
      
      echo "Found ROSA security groups: $SG_IDS"
      
      # Function to delete rules (ingress or egress)
      delete_rules() {
        local sg_id="$1"
        local rule_type="$2"  # "ingress" or "egress"
        local is_egress_value="$3"  # "true" or "false"
        
        # Get all rules using newer API
        local rule_ids=$(aws ec2 describe-security-group-rules \
          --region "$REGION" \
          --filters "Name=group-id,Values=$sg_id" \
          --query "SecurityGroupRules[?IsEgress==\`$is_egress_value\`].SecurityGroupRuleId" \
          --output text 2>/dev/null || echo "")
      
        # If no rules found with newer API, try alternative query (without filters)
        if [ -z "$rule_ids" ]; then
          rule_ids=$(aws ec2 describe-security-group-rules \
            --region "$REGION" \
            --group-ids "$sg_id" \
            --query "SecurityGroupRules[?IsEgress==\`$is_egress_value\`].SecurityGroupRuleId" \
            --output text 2>/dev/null || echo "")
        fi
      
        # If still no rules, check using describe-security-groups to see if rules exist
        local rules_count="0"
        if [ -z "$rule_ids" ]; then
          if [ "$rule_type" = "ingress" ]; then
            rules_count=$(aws ec2 describe-security-groups \
              --region "$REGION" \
              --group-ids "$sg_id" \
              --query "SecurityGroups[0].IpPermissions | length(@)" \
              --output text 2>/dev/null || echo "0")
            local permissions_key="IpPermissions"
          else
            rules_count=$(aws ec2 describe-security-groups \
              --region "$REGION" \
              --group-ids "$sg_id" \
              --query "SecurityGroups[0].IpPermissionsEgress | length(@)" \
              --output text 2>/dev/null || echo "0")
            local permissions_key="IpPermissionsEgress"
          fi
          
          if [ "$rules_count" != "0" ] && [ "$rules_count" != "None" ]; then
            echo "  Found $rules_count $rule_type rule(s) but could not get rule IDs - attempting to delete by rule details"
            # Use revoke-security-group-* with rule details
            aws ec2 describe-security-groups \
              --region "$REGION" \
              --group-ids "$sg_id" \
              --query "SecurityGroups[0].$permissions_key" \
              --output json 2>/dev/null | \
            jq -r '.[] | "--ip-protocol \(.IpProtocol) --from-port \(.FromPort // 0) --to-port \(.ToPort // 0) " + (if .IpRanges and (.IpRanges | length > 0) then "--cidr \(.IpRanges[0].CidrIp)" else "" end)' | \
            while read -r revoke_args; do
              if [ -n "$revoke_args" ]; then
                echo "    Deleting $rule_type rule: $revoke_args"
                if [ "$rule_type" = "ingress" ]; then
                  eval "aws ec2 revoke-security-group-ingress --region \"$REGION\" --group-id \"$sg_id\" $revoke_args" 2>/dev/null || true
                else
                  eval "aws ec2 revoke-security-group-egress --region \"$REGION\" --group-id \"$sg_id\" $revoke_args" 2>/dev/null || true
                fi
              fi
            done
          fi
        fi
      
        # Delete rules by rule ID if we found them
        if [ -n "$rule_ids" ]; then
          local rule_count=$(echo $rule_ids | wc -w)
          echo "  Found $rule_count $rule_type rule(s) to delete"
          for rule_id in $rule_ids; do
            echo "    Deleting $rule_type rule $rule_id..."
            # Try newer API first, fall back to older API
            if ! aws ec2 delete-security-group-rule --region "$REGION" --group-id "$sg_id" --group-rule-id "$rule_id" 2>/dev/null; then
              if [ "$rule_type" = "ingress" ]; then
                aws ec2 revoke-security-group-ingress --region "$REGION" --group-id "$sg_id" --security-group-rule-ids "$rule_id" 2>/dev/null || echo "    Could not delete $rule_type rule $rule_id (may already be deleted)"
              else
                aws ec2 revoke-security-group-egress --region "$REGION" --group-id "$sg_id" --security-group-rule-ids "$rule_id" 2>/dev/null || echo "    Could not delete $rule_type rule $rule_id (may already be deleted)"
              fi
            fi
          done
        else
          if [ "$rules_count" = "0" ] || [ -z "$rules_count" ] || [ "$rules_count" = "None" ]; then
            echo "  No $rule_type rules found"
          fi
        fi
      }
      
      # For each security group, delete ingress rules, egress rules, then the group
      for sg_id in $SG_IDS; do
        echo "Cleaning up security group $sg_id..."
        
        # Get security group details for logging
        SG_NAME=$(aws ec2 describe-security-groups \
          --region "$REGION" \
          --group-ids "$sg_id" \
          --query 'SecurityGroups[0].GroupName' \
          --output text 2>/dev/null || echo "unknown")
        echo "  Security group name: $SG_NAME"
        
        # Delete ingress rules
        delete_rules "$sg_id" "ingress" "false"
        
        # Delete egress rules
        delete_rules "$sg_id" "egress" "true"
        
        # Delete the security group
        echo "  Deleting security group $sg_id..."
        if ! DELETE_OUTPUT=$(aws ec2 delete-security-group --region "$REGION" --group-id "$sg_id" 2>&1); then
          echo "  Warning: Could not delete security group $sg_id:"
          echo "$DELETE_OUTPUT" | sed "s/^/    /"
        else
          echo "  Successfully deleted security group $sg_id"
        fi
      done
      
      echo "ROSA security group cleanup complete"
    EOT
  }

  # No explicit depends_on needed - implicit dependencies from triggers ensure correct destroy order
  # The cleanup resource references cluster and child resources in triggers, so Terraform will:
  # 1. Destroy child resources first (they depend on cluster)
  # 2. Destroy cluster second
  # 3. Destroy cleanup last (it references all of them)
}
