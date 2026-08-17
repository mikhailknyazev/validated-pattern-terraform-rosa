# Route Server Module

AWS VPC Route Server for BGP routing with the [CUDN BGP routing operator](https://github.com/jingczhang/rosa-bgp-operator).

## What it creates

- **VPC Route Server** with configurable Amazon-side ASN
- **Route Server endpoints** (2 per private subnet) for BGP peering
- **Route propagation** to private and public route tables
- **IAM role and policy** for the CUDN BGP routing operator (IRSA)
- **Secrets Manager secret** `{cluster_name}-bgp-config` with runtime params for ESO (issue #51)
- Optional **IAM inline policy** on the ESO role granting read of that secret

## How it works with the operator

1. Terraform creates the Route Server, endpoints, IAM role, and BGP config secret
2. External Secrets Operator syncs `{cluster}-bgp-config` into the cluster (when ESO is installed)
3. The cudn-bgp-routing-operator chart applies role ARN / region / routeServerIDs from the synced Secret
4. The BGP operator discovers endpoints via `DescribeRouteServerEndpoints` and manages peers/FRR

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| cluster_name | Name prefix for resources | string | - | yes |
| region | AWS region (written into BGP config secret) | string | - | yes |
| vpc_id | VPC to associate Route Server with | string | - | yes |
| private_subnet_ids | Private subnets for endpoints (2 per subnet) | list(string) | - | yes |
| private_route_table_ids | Private route tables for propagation | list(string) | - | yes |
| public_route_table_ids | Public route tables for propagation | list(string) | [] | no |
| oidc_endpoint_url | OIDC endpoint URL for IRSA trust | string | - | yes |
| route_server_asn | Amazon-side ASN | number | 64512 | no |
| persist_routes | Persist routes on BGP session loss | string | "disable" | no |
| secrets_manager_role_name | ESO IAM role name for secret read policy | string | null | no |
| tags | Tags for all resources | map(string) | {} | no |
| persists_through_sleep | Sleep mode gating | bool | true | no |
| custom_permissions_boundary_arn | Permission boundary for IAM role | string | null | no |

## Outputs

| Name | Description |
|------|-------------|
| route_server_id | Route Server ID (for CUDNBgpConfig CR `spec.aws.routeServerIDs`) |
| route_server_asn | Amazon-side ASN |
| endpoint_ips | Map of endpoint key to ENI IP address |
| endpoint_details | Map of endpoint key to full details |
| bgp_operator_role_arn | IAM role ARN (for ServiceAccount annotation) |
| bgp_config_secret_name | Secrets Manager secret name for ESO (`{cluster}-bgp-config`) |
| bgp_config_secret_arn | Secrets Manager secret ARN |

## GitOps / ESO (preferred)

1. Set `enable_secrets_manager_iam = true` and `enable_route_server = true`
2. Install the `external-secrets-operator` chart with `serviceAccount.roleArn` from `terraform output -raw secrets_manager_role_arn` (or `external_secrets_role_arn`)
3. Enable `externalSecret` on the `cudn-bgp-routing-operator` chart with `remoteKey: <cluster>-bgp-config`

Manual SA annotation is only needed if ESO / chart automation is not used.