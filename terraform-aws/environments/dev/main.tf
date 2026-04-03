module "network" {
  source = "../../modules/network"

  availability_zone = var.availability_zone
  management_cidrs  = var.management_cidrs
  name_prefix       = local.name_prefix
  tags              = local.common_tags
}

module "security" {
  source = "../../modules/security"

  management_cidrs = var.management_cidrs
  name_prefix      = local.name_prefix
  tags             = local.common_tags
  vpc_cidrs        = module.network.vpc_cidrs
  vpc_ids          = module.network.vpc_ids
}

module "compute" {
  source = "../../modules/compute"

  name_prefix        = local.name_prefix
  public_key         = var.public_key
  security_group_ids = module.security.security_group_ids
  subnet_ids         = module.network.subnet_ids
  tags               = local.common_tags
}
