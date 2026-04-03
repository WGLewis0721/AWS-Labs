output "environment" {
  description = "Environment name."
  value       = local.environment
}

output "name_prefix" {
  description = "Resource name prefix used in this environment."
  value       = local.name_prefix
}

output "common_tags" {
  description = "Resolved tag map applied across modules."
  value       = local.common_tags
}
