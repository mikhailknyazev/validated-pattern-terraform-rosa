# AWS VPC Route Server for BGP routing with the CUDN BGP routing operator.
# Creates a Route Server with 2 endpoints per private subnet and propagation
# to all route tables. The operator discovers endpoints automatically via
# DescribeRouteServerEndpoints.

resource "aws_vpc_route_server" "this" {
  count = var.persists_through_sleep ? 1 : 0

  amazon_side_asn           = var.route_server_asn
  persist_routes            = var.persist_routes
  sns_notifications_enabled = false

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-route-server"
  })
}

resource "aws_vpc_route_server_vpc_association" "this" {
  count = var.persists_through_sleep ? 1 : 0

  route_server_id = aws_vpc_route_server.this[0].route_server_id
  vpc_id          = var.vpc_id
}

# Route Server Endpoints - 2 per private subnet using for_each.
# Keys: "0-0", "0-1", "1-0", "1-1", etc. (subnet_index-endpoint_index)
resource "aws_vpc_route_server_endpoint" "this" {
  for_each = var.persists_through_sleep ? {
    for pair in flatten([
      for idx, subnet_id in var.private_subnet_ids : [
        { key = "${idx}-0", subnet_id = subnet_id, ep_index = 0, subnet_index = idx },
        { key = "${idx}-1", subnet_id = subnet_id, ep_index = 1, subnet_index = idx },
      ]
    ]) : pair.key => pair
  } : {}

  route_server_id = aws_vpc_route_server.this[0].route_server_id
  subnet_id       = each.value.subnet_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-rs-subnet${each.value.subnet_index}-ep${each.value.ep_index}"
  })

  depends_on = [aws_vpc_route_server_vpc_association.this]
}

# Propagation to private route tables
resource "aws_vpc_route_server_propagation" "private" {
  count = var.persists_through_sleep ? length(var.private_route_table_ids) : 0

  route_server_id = aws_vpc_route_server.this[0].route_server_id
  route_table_id  = var.private_route_table_ids[count.index]

  depends_on = [aws_vpc_route_server_vpc_association.this]
}

# Propagation to public route tables (if any)
resource "aws_vpc_route_server_propagation" "public" {
  count = var.persists_through_sleep ? length(var.public_route_table_ids) : 0

  route_server_id = aws_vpc_route_server.this[0].route_server_id
  route_table_id  = var.public_route_table_ids[count.index]

  depends_on = [aws_vpc_route_server_vpc_association.this]
}
