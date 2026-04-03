module "network" {
  source = "../../modules/network"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "security" {
  source = "../../modules/security"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "compute" {
  source = "../../modules/compute"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "storage" {
  source = "../../modules/storage"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}
