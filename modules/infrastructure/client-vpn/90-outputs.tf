#------------------------------------------------------------------------------
# Client VPN Module Outputs
#
# Reference: ./reference/rosa-tf/modules/networking/client-vpn/outputs.tf
#------------------------------------------------------------------------------

output "vpn_endpoint_id" {
  description = "ID of the Client VPN endpoint."
  value       = aws_ec2_client_vpn_endpoint.this.id
  sensitive   = false
}

output "vpn_endpoint_dns" {
  description = "DNS name of the Client VPN endpoint."
  value       = aws_ec2_client_vpn_endpoint.this.dns_name
  sensitive   = false
}

output "vpn_endpoint_arn" {
  description = "ARN of the Client VPN endpoint."
  value       = aws_ec2_client_vpn_endpoint.this.arn
  sensitive   = false
}

output "client_config_path" {
  description = "Path to the generated OpenVPN client configuration file."
  value       = local_file.client_config.filename
  sensitive   = false
}

output "security_group_id" {
  description = "ID of the VPN security group."
  value       = aws_security_group.vpn.id
  sensitive   = false
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for VPN logs."
  value       = aws_cloudwatch_log_group.vpn.name
  sensitive   = false
}

output "certificate_expiry" {
  description = "Expiry date of the client certificate."
  value       = tls_locally_signed_cert.client.validity_end_time
  sensitive   = false
}

output "connection_instructions" {
  description = "Instructions for connecting to the VPN."
  value       = <<-EOT

================================================================================
AWS Client VPN Connection Instructions - ${var.cluster_name}
================================================================================

1. INSTALL VPN CLIENT

   Option A - AWS VPN Client (recommended):
   Download from: https://aws.amazon.com/vpn/client-vpn-download/

   Option B - OpenVPN Client:
   macOS:    brew install openvpn
   Linux:    sudo apt install openvpn
   Windows:  https://openvpn.net/community-downloads/

2. IMPORT CONFIGURATION

   Configuration file: ${coalesce(var.client_config_display_path, local_file.client_config.filename)}

   AWS VPN Client:
   - File > Manage Profiles > Add Profile
   - Browse to the .ovpn file

   OpenVPN CLI:
   sudo openvpn --config ${coalesce(var.client_config_display_path, local_file.client_config.filename)}

3. CONNECT TO VPN

   After connecting, you can directly access the cluster API and console.
   Use: terraform output api_url and terraform output console_url for URLs.

4. VERIFY CONNECTION

   # Check VPC connectivity (replace with your VPC CIDR)
   ping ${cidrhost(var.vpc_cidr, 1)}

   # Test cluster API (after getting URL from terraform output api_url)
   curl -k https://api.<cluster-domain>:6443/healthz

================================================================================
Certificate expires: ${tls_locally_signed_cert.client.validity_end_time}
================================================================================
EOT
  sensitive   = false
}
