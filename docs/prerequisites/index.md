# Prerequisites — Choose Your Path

Before deploying a ROSA HCP cluster, determine **who owns each infrastructure layer** and **what egress/API posture** you need.

## Three questions

1. **Does one team run the full Terraform lifecycle from this repo?**  
   → [Full-Stack Deployment](full-stack.md)

2. **Does another team pre-provision the VPC (or other infrastructure)?**  
   → [Bring Your Own — Overview](byo/index.md)

3. **Is this a zero-egress cluster?**  
   → Apply the zero-egress overlay in [Network Requirements](byo/network.md) (works with full-stack or BYO)

## Decision tree

```mermaid
flowchart TD
  Start[Start deployment planning]
  Start --> Account[Layer 0: Account prerequisites]
  Account --> Owner{Who runs Terraform?}

  Owner -->|One platform team| FullStack[Layer 1: Full-stack]
  Owner -->|Network team owns VPC| BYONet[Layer 2a: BYO network]
  Owner -->|Network + IAM teams| BYOAll[Layer 2a + 2b: BYO network and IAM]

  FullStack --> EgressQ{zero_egress=true?}
  BYONet --> EgressQ
  BYOAll --> EgressQ

  EgressQ -->|Yes| ZeroOverlay[Zero egress: VPC endpoints only, no NAT]
  EgressQ -->|No| StandardOverlay[Standard: NAT or user-managed egress]

  ZeroOverlay --> Validate[Run validation scripts]
  StandardOverlay --> Validate
  Validate --> Apply[make cluster.name.apply]
```

## Layers summary

| Layer | Scope | Document | Validation |
|-------|-------|----------|------------|
| **0 — Account** | AWS account, ROSA Marketplace, quotas, operator tools | [Account Prerequisites](account.md) | `make cluster.<name>.validate` |
| **1 — Full-stack** | Terraform creates VPC, IAM, cluster | [Full-Stack Deployment](full-stack.md) | Account validation before init |
| **2a — BYO network** | Pre-provisioned VPC, subnets, endpoints | [BYO Network](byo/network.md) | `make cluster.<name>.validate-network` |
| **2b — BYO IAM/KMS** | Separate security team owns roles/keys | [BYO IAM and KMS](byo/iam-kms.md) | Manual handoff checklist |

## Customer intake

For delivery teams collecting requirements from a customer, use the [Customer Intake Form](customer-intake.md).

## Related

- [Enablement Guide](../deployment/enablement.md) — full adoption path
- [Cluster Configurations](../deployment/cluster-configurations.md) — example tfvars
- [Validation Scripts](../operations/validation.md)
