# Covers: description, value
# Does: Exposes the owning-API identifier and stable display name to callers.
# Why: Callers need both values for resource-bound verification after apply.
# Change: Removing either output forces callers to infer identity from local addresses.
# Trap: Output presence proves Terraform state only, not management-plane realization.
# Evidence: https://developer.hashicorp.com/terraform/language/values/outputs
output "id" {
  description = "RHCS identity-provider identifier after creation."
  value       = rhcs_identity_provider.this.id
}

output "name" {
  description = "Stable identity-provider name supplied by the caller."
  value       = rhcs_identity_provider.this.name
}
