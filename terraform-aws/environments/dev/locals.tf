locals {
  environment = "dev"
  name_prefix = var.name_prefix

  common_tags = merge(
    {
      Environment = local.environment
      ManagedBy   = "terraform"
    },
    var.common_tags
  )
}