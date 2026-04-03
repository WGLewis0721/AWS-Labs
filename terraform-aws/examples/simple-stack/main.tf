module "network" {
  source = "../../modules/network"

  name_prefix = "example"
}

module "security" {
  source = "../../modules/security"

  name_prefix = "example"
}

module "compute" {
  source = "../../modules/compute"

  name_prefix = "example"
}

module "storage" {
  source = "../../modules/storage"

  name_prefix = "example"
}
