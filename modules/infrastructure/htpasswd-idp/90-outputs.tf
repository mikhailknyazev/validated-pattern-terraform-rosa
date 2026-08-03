output "enabled" {
  description = "Whether HTPasswd IDP resources are enabled/created"
  value       = local.create
  sensitive   = false
}

# Outputs reference created resources so terraform apply -target updates them in state.
output "username" {
  description = "HTPasswd username (null when disabled)"
  value       = try(rhcs_identity_provider.this[0].htpasswd.users[0].username, null)
  sensitive   = false
}

output "password" {
  description = "HTPasswd password (null when disabled). Sensitive — not stored in Secrets Manager by this module."
  value       = local.password
  sensitive   = true
}

output "idp_name" {
  description = "HTPasswd identity provider name (null when disabled)"
  value       = try(rhcs_identity_provider.this[0].name, null)
  sensitive   = false
}

output "identity_provider_id" {
  description = "RHCS identity provider ID (null when disabled)"
  value       = try(rhcs_identity_provider.this[0].id, null)
  sensitive   = false
}
