module "network" {
  source = "../../modules/network"

  name_prefix = var.name_prefix
  tags        = var.common_tags
}

module "security" {
  source = "../../modules/security"

  name_prefix = var.name_prefix
  tags        = var.common_tags
}

module "compute" {
  source = "../../modules/compute"

  name_prefix = var.name_prefix
  tags        = var.common_tags
}

module "storage" {
  source = "../../modules/storage"

  name_prefix = var.name_prefix
  tags        = var.common_tags
}
