#------------------------------------------------------------------------------
# AWS Client VPN Module for ROSA HCP
#
# This module creates an AWS Client VPN endpoint for secure access to the
# private VPC hosting the ROSA cluster. Recommended alternative to sshuttle/bastion.
#
# Features:
#   - Direct network connectivity to the VPC
#   - VPC DNS resolution for cluster endpoints
#   - No port forwarding or tunneling required
#   - Native access to cluster API and console
#
# Authentication: Mutual TLS (self-signed CA + server/client certs)
# Reference: ./reference/rosa-tf/modules/networking/client-vpn/main.tf
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# TLS Certificates for Mutual Authentication
#------------------------------------------------------------------------------

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${var.cluster_name}-vpn-ca"
    organization = var.certificate_organization
  }

  validity_period_hours = var.certificate_validity_days * 24
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# AWS Client VPN requires a domain name in the certificate's SAN
resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = "server.${var.cluster_name}.vpn.internal"
    organization = var.certificate_organization
  }

  dns_names = [
    "server.${var.cluster_name}.vpn.internal",
    "${var.cluster_name}-vpn-server",
  ]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.certificate_validity_days * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = "${var.cluster_name}-vpn-client"
    organization = var.certificate_organization
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.certificate_validity_days * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

#------------------------------------------------------------------------------
# Import Certificates to ACM
#------------------------------------------------------------------------------

resource "aws_acm_certificate" "server" {
  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-vpn-server-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "client" {
  private_key       = tls_private_key.client.private_key_pem
  certificate_body  = tls_locally_signed_cert.client.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-vpn-client-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# CloudWatch Log Group for VPN Connection Logs
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/vpn/${var.cluster_name}-client-vpn"
  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-vpn-logs"
  })
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "connection-logs"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

#------------------------------------------------------------------------------
# Security Group for VPN Endpoint
#------------------------------------------------------------------------------

resource "aws_security_group" "vpn" {
  name        = "${var.cluster_name}-client-vpn"
  description = "Security group for Client VPN endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description = "All traffic from VPN clients"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.client_cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-client-vpn-sg"
  })
}

#------------------------------------------------------------------------------
# Client VPN Endpoint
#------------------------------------------------------------------------------

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "Client VPN for ${var.cluster_name} ROSA HCP cluster access"
  server_certificate_arn = aws_acm_certificate.server.arn
  client_cidr_block      = var.client_cidr_block

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.client.arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  dns_servers = var.dns_servers

  split_tunnel = var.split_tunnel

  transport_protocol = "udp"
  vpn_port           = 443

  security_group_ids = [aws_security_group.vpn.id]
  vpc_id             = var.vpc_id

  session_timeout_hours = var.session_timeout_hours

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-client-vpn"
  })
}

#------------------------------------------------------------------------------
# VPN Network Associations (attach to subnets)
#------------------------------------------------------------------------------

resource "aws_ec2_client_vpn_network_association" "this" {
  count = length(var.subnet_ids)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.subnet_ids[count.index]

  timeouts {
    create = "30m"
    delete = "30m"
  }
}

#------------------------------------------------------------------------------
# Authorization Rules
#------------------------------------------------------------------------------

resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Allow access to VPC CIDR"

  timeouts {
    create = "15m"
    delete = "15m"
  }
}

resource "aws_ec2_client_vpn_authorization_rule" "service_cidr" {
  count = var.service_cidr != null ? 1 : 0

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.service_cidr
  authorize_all_groups   = true
  description            = "Allow access to cluster service CIDR"

  timeouts {
    create = "15m"
    delete = "15m"
  }
}

#------------------------------------------------------------------------------
# Generate OpenVPN Client Configuration File
#------------------------------------------------------------------------------

locals {
  cluster_domain_note = var.cluster_domain != null ? "#      - API: https://api.${var.cluster_domain}:6443\n#      - Console: https://console-openshift-console.apps.${var.cluster_domain}" : "#      - Use cluster API and console URLs from cluster outputs"
}

resource "local_file" "client_config" {
  filename = "${var.output_dir}/${var.cluster_name}-vpn-client.ovpn"
  content  = <<-EOT
# OpenVPN Client Configuration for ${var.cluster_name}
# Generated by Terraform - AWS Client VPN
#
# USAGE:
#   1. Install OpenVPN client (or AWS VPN Client)
#   2. Import this .ovpn file
#   3. Connect to the VPN
#   4. Access cluster endpoints directly:
${local.cluster_domain_note}
#
# CERTIFICATE VALIDITY: ${var.certificate_validity_days} days
# Generated: ${timestamp()}

client
dev tun
proto udp
remote ${replace(aws_ec2_client_vpn_endpoint.this.dns_name, "*.", "")} 443
remote-random-hostname
resolv-retry infinite
nobind
remote-cert-tls server
cipher AES-256-GCM
verb 3

<ca>
${tls_self_signed_cert.ca.cert_pem}
</ca>

<cert>
${tls_locally_signed_cert.client.cert_pem}
</cert>

<key>
${tls_private_key.client.private_key_pem}
</key>

reneg-sec 0
EOT

  file_permission = "0600"

  depends_on = [aws_ec2_client_vpn_endpoint.this]
}

#------------------------------------------------------------------------------
# Output certificates for backup/rotation
#------------------------------------------------------------------------------

resource "local_sensitive_file" "client_key" {
  filename        = "${var.output_dir}/${var.cluster_name}-vpn-client.key"
  content         = tls_private_key.client.private_key_pem
  file_permission = "0600"
}
