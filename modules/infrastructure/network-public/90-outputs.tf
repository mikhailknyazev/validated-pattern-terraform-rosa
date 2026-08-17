output "vpc_id" {
  description = "ID of the VPC (null if persists_through_sleep_network is false)"
  value       = length(aws_vpc.main) > 0 ? one(aws_vpc.main[*].id) : null
  sensitive   = false
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC (null if persists_through_sleep_network is false)"
  value       = length(aws_vpc.main) > 0 ? one(aws_vpc.main[*].cidr_block) : null
  sensitive   = false
}

output "private_subnet_ids" {
  description = "List of private subnet IDs (empty if persists_through_sleep_network is false)"
  value       = aws_subnet.private[*].id
  sensitive   = false
}

output "public_subnet_ids" {
  description = "List of public subnet IDs (empty if persists_through_sleep_network is false)"
  value       = aws_subnet.public[*].id
  sensitive   = false
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs (one per AZ, empty if persists_through_sleep_network is false)"
  value       = aws_nat_gateway.main[*].id
  sensitive   = false
}

output "nat_gateway_id" {
  description = "ID of the first NAT Gateway (for backwards compatibility, null if persists_through_sleep_network is false)"
  value       = length(aws_nat_gateway.main) > 0 ? aws_nat_gateway.main[0].id : null
  sensitive   = false
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway (null if persists_through_sleep_network is false)"
  value       = length(aws_internet_gateway.main) > 0 ? one(aws_internet_gateway.main[*].id) : null
  sensitive   = false
}

output "vpc_endpoint_ids" {
  description = "Map of VPC endpoint service names to endpoint IDs (empty if persists_through_sleep_network is false)"
  value = length(aws_vpc_endpoint.s3) > 0 ? {
    s3      = one(aws_vpc_endpoint.s3[*].id)
    ecr_dkr = one(aws_vpc_endpoint.ecr_dkr[*].id)
    ecr_api = one(aws_vpc_endpoint.ecr_api[*].id)
    sts     = one(aws_vpc_endpoint.sts[*].id)
  } : {}
  sensitive = false
}

output "private_subnet_azs" {
  description = "List of availability zones used for private subnets (empty if persists_through_sleep_network is false)"
  value       = aws_subnet.private[*].availability_zone
  sensitive   = false
}

output "public_subnet_azs" {
  description = "List of availability zones used for public subnets (empty if persists_through_sleep_network is false)"
  value       = aws_subnet.public[*].availability_zone
  sensitive   = false
}

output "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (empty if persists_through_sleep_network is false)"
  value       = aws_subnet.private[*].cidr_block
  sensitive   = false
}

output "private_route_table_ids" {
  description = "List of private subnet route table IDs (empty if persists_through_sleep_network is false)"
  value       = aws_route_table.private[*].id
  sensitive   = false
}

output "public_route_table_ids" {
  description = "List of public subnet route table IDs (empty if persists_through_sleep_network is false)"
  value       = aws_route_table.public[*].id
  sensitive   = false
}
