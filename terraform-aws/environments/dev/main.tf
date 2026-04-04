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

# Preserve the original lab subnets that were split into per-role names
# during the architecture refactor.
moved {
  from = module.network.aws_subnet.this["b"]
  to   = module.network.aws_subnet.this["b_untrust"]
}

moved {
  from = module.network.aws_subnet.this["c"]
  to   = module.network.aws_subnet.this["c_dmz"]
}
