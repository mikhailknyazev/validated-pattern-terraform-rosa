output "enabled" {
  description = "Whether the bootstrap admin resources are enabled"
  value       = module.idp.enabled
  sensitive   = false
}

output "username" {
  description = "Bootstrap HTPasswd username (null when disabled)"
  value       = module.idp.username
  sensitive   = false
}

output "password" {
  description = "Bootstrap HTPasswd password (null when disabled). Sensitive output only — not stored in Secrets Manager. Prefer the caller-supplied password when using bootstrap-admin.sh."
  value       = module.idp.password
  sensitive   = true
}

output "idp_name" {
  description = "HTPasswd identity provider name (null when disabled)"
  value       = module.idp.idp_name
  sensitive   = false
}

output "identity_provider_id" {
  description = "RHCS identity provider ID (null when disabled)"
  value       = module.idp.identity_provider_id
  sensitive   = false
}
