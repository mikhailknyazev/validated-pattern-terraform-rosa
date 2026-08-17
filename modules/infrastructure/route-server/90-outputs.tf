output "route_server_id" {
  description = "ID of the VPC Route Server (null if persists_through_sleep is false)"
  value       = length(aws_vpc_route_server.this) > 0 ? aws_vpc_route_server.this[0].route_server_id : null
  sensitive   = false
}

output "route_server_asn" {
  description = "Amazon-side ASN of the Route Server"
  value       = length(aws_vpc_route_server.this) > 0 ? aws_vpc_route_server.this[0].amazon_side_asn : null
  sensitive   = false
}

output "endpoint_ips" {
  description = "Map of endpoint key to ENI IP address (e.g., '0-0' => '10.x.y.z')"
  value = {
    for key, ep in aws_vpc_route_server_endpoint.this : key => ep.eni_address
  }
  sensitive = false
}

output "endpoint_details" {
  description = "Map of endpoint key to details (subnet_id, eni_address, endpoint_id)"
  value = {
    for key, ep in aws_vpc_route_server_endpoint.this : key => {
      endpoint_id = ep.route_server_endpoint_id
      eni_address = ep.eni_address
      subnet_id   = ep.subnet_id
    }
  }
  sensitive = false
}

output "bgp_operator_role_arn" {
  description = "ARN of the IAM role for the CUDN BGP routing operator (for IRSA ServiceAccount annotation)"
  value       = length(aws_iam_role.bgp_operator) > 0 ? aws_iam_role.bgp_operator[0].arn : null
  sensitive   = false
}

output "bgp_config_secret_name" {
  description = "Secrets Manager secret name with BGP runtime config for ESO (null if Route Server not deployed)"
  value       = length(aws_secretsmanager_secret.bgp_config) > 0 ? aws_secretsmanager_secret.bgp_config[0].name : null
  sensitive   = false
}

output "bgp_config_secret_arn" {
  description = "Secrets Manager secret ARN with BGP runtime config for ESO (null if Route Server not deployed)"
  value       = length(aws_secretsmanager_secret.bgp_config) > 0 ? aws_secretsmanager_secret.bgp_config[0].arn : null
  sensitive   = false
}
