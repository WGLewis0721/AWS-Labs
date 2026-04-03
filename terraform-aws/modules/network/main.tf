terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}


locals {
  selected_az = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])

  vpcs = {
    a = { cidr = "10.0.0.0/16", name = "lab-vpc-a-cloudhost" }
    b = { cidr = "10.1.0.0/16", name = "lab-vpc-b-paloalto" }
    c = { cidr = "10.2.0.0/16", name = "lab-vpc-c-appgate" }
    d = { cidr = "10.3.0.0/16", name = "lab-vpc-d-customer" }
  }

  subnets = {
    a            = { cidr = "10.0.1.0/24", vpc_key = "a", name = "lab-subnet-a-public" }
    b_untrust    = { cidr = "10.1.1.0/24", vpc_key = "b", name = "lab-subnet-b-untrust" }
    b_trust      = { cidr = "10.1.2.0/24", vpc_key = "b", name = "lab-subnet-b-trust" }
    b_mgmt       = { cidr = "10.1.3.0/24", vpc_key = "b", name = "lab-subnet-b-mgmt" }
    c_dmz        = { cidr = "10.2.1.0/24", vpc_key = "c", name = "lab-subnet-c-dmz" }
    c_portal     = { cidr = "10.2.2.0/24", vpc_key = "c", name = "lab-subnet-c-portal" }
    c_gateway    = { cidr = "10.2.3.0/24", vpc_key = "c", name = "lab-subnet-c-gateway" }
    c_controller = { cidr = "10.2.4.0/24", vpc_key = "c", name = "lab-subnet-c-controller" }
    d            = { cidr = "10.3.1.0/24", vpc_key = "d", name = "lab-subnet-d-private" }
  }

  transit_gateways = {
    tgw1 = { amazon_side_asn = 64512, name = "lab-tgw1-mgmt",     route_table = "tgw1-rt-mgmt" }
    tgw2 = { amazon_side_asn = 64513, name = "lab-tgw2-customer", route_table = "tgw2-rt-customer" }
  }

  attachment_definitions = {
    tgw1_a = { name = "tgw1-attach-vpc-a", subnet = "a",       tgw_key = "tgw1", vpc_key = "a" }
    tgw1_b = { name = "tgw1-attach-vpc-b", subnet = "b_trust", tgw_key = "tgw1", vpc_key = "b" }
    tgw1_c = { name = "tgw1-attach-vpc-c", subnet = "c_dmz",   tgw_key = "tgw1", vpc_key = "c" }
    tgw2_b = { name = "tgw2-attach-vpc-b", subnet = "b_trust", tgw_key = "tgw2", vpc_key = "b" }
    tgw2_c = { name = "tgw2-attach-vpc-c", subnet = "c_dmz",   tgw_key = "tgw2", vpc_key = "c" }
    tgw2_d = { name = "tgw2-attach-vpc-d", subnet = "d",       tgw_key = "tgw2", vpc_key = "d" }
  }

  # Route entries keyed by unique name; igw/tgw are nullable strings.
  route_entries = {
    "a-internet"            = { subnet = "a",            destination = "0.0.0.0/0",   igw = "a",    tgw = null }
    "a-to-b"                = { subnet = "a",            destination = "10.1.0.0/16", igw = null,   tgw = "tgw1" }
    "a-to-c"                = { subnet = "a",            destination = "10.2.0.0/16", igw = null,   tgw = "tgw1" }
    "b_untrust-internet"    = { subnet = "b_untrust",    destination = "0.0.0.0/0",   igw = "b",    tgw = null }
    "b_trust-to-a"          = { subnet = "b_trust",      destination = "10.0.0.0/16", igw = null,   tgw = "tgw1" }
    "b_trust-to-c"          = { subnet = "b_trust",      destination = "10.2.0.0/16", igw = null,   tgw = "tgw1" }
    "b_trust-to-d"          = { subnet = "b_trust",      destination = "10.3.0.0/16", igw = null,   tgw = "tgw2" }
    "b_trust-internet"      = { subnet = "b_trust",      destination = "0.0.0.0/0",   igw = null,   tgw = "tgw1" }
    "b_mgmt-to-a"           = { subnet = "b_mgmt",       destination = "10.0.0.0/16", igw = null,   tgw = "tgw1" }
    "b_mgmt-internet"       = { subnet = "b_mgmt",       destination = "0.0.0.0/0",   igw = null,   tgw = "tgw1" }
    "c_dmz-to-b"            = { subnet = "c_dmz",        destination = "10.1.0.0/16", igw = null,   tgw = "tgw1" }
    "c_dmz-to-a"            = { subnet = "c_dmz",        destination = "10.0.0.0/16", igw = null,   tgw = "tgw1" }
    "c_dmz-internet"        = { subnet = "c_dmz",        destination = "0.0.0.0/0",   igw = null,   tgw = "tgw1" }
    "c_portal-to-b"         = { subnet = "c_portal",     destination = "10.1.0.0/16", igw = null,   tgw = "tgw1" }
    "c_portal-to-a"         = { subnet = "c_portal",     destination = "10.0.0.0/16", igw = null,   tgw = "tgw1" }
    "c_portal-internet"     = { subnet = "c_portal",     destination = "0.0.0.0/0",   igw = null,   tgw = "tgw1" }
    "c_gateway-to-b"        = { subnet = "c_gateway",    destination = "10.1.0.0/16", igw = null,   tgw = "tgw1" }
    "c_gateway-to-a"        = { subnet = "c_gateway",    destination = "10.0.0.0/16", igw = null,   tgw = "tgw1" }
    "c_gateway-internet"    = { subnet = "c_gateway",    destination = "0.0.0.0/0",   igw = null,   tgw = "tgw1" }
    "c_controller-to-b"     = { subnet = "c_controller", destination = "10.1.0.0/16", igw = null,   tgw = "tgw1" }
    "c_controller-to-a"     = { subnet = "c_controller", destination = "10.0.0.0/16", igw = null,   tgw = "tgw1" }
    "c_controller-internet" = { subnet = "c_controller", destination = "0.0.0.0/0",   igw = null,   tgw = "tgw1" }
    "d-to-b"                = { subnet = "d",            destination = "10.1.0.0/16", igw = null,   tgw = "tgw2" }
    "d-to-c"                = { subnet = "d",            destination = "10.2.0.0/16", igw = null,   tgw = "tgw2" }
    "d-internet"            = { subnet = "d",            destination = "0.0.0.0/0",   igw = null,   tgw = "tgw2" }
  }

  tgw_route_entries = {
    tgw1_route_a       = { attachment_key = "tgw1_a", cidr = "10.0.0.0/16", route_table = "tgw1" }
    tgw1_route_b       = { attachment_key = "tgw1_b", cidr = "10.1.0.0/16", route_table = "tgw1" }
    tgw1_route_c       = { attachment_key = "tgw1_c", cidr = "10.2.0.0/16", route_table = "tgw1" }
    tgw1_route_default = { attachment_key = "tgw1_a", cidr = "0.0.0.0/0",   route_table = "tgw1" }
    tgw2_route_b       = { attachment_key = "tgw2_b", cidr = "10.1.0.0/16", route_table = "tgw2" }
    tgw2_route_c       = { attachment_key = "tgw2_c", cidr = "10.2.0.0/16", route_table = "tgw2" }
    tgw2_route_d       = { attachment_key = "tgw2_d", cidr = "10.3.0.0/16", route_table = "tgw2" }
    tgw2_route_default = { attachment_key = "tgw2_b", cidr = "0.0.0.0/0",   route_table = "tgw2" }
  }

  tgw_associations = {
    tgw1_a = { attachment_key = "tgw1_a", route_table = "tgw1" }
    tgw1_b = { attachment_key = "tgw1_b", route_table = "tgw1" }
    tgw1_c = { attachment_key = "tgw1_c", route_table = "tgw1" }
    tgw2_b = { attachment_key = "tgw2_b", route_table = "tgw2" }
    tgw2_c = { attachment_key = "tgw2_c", route_table = "tgw2" }
    tgw2_d = { attachment_key = "tgw2_d", route_table = "tgw2" }
  }

  # Flat list of NACL rules. For ICMP rules from_port = icmp_type, to_port = icmp_code.
  nacl_rules = [
    # ── nacl "a" (subnet-a-public) ──────────────────────────────────────
    # Inbound
    { acl = "a", egress = false, rule_number = 100, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 3389, to_port = 3389 },
    { acl = "a", egress = false, rule_number = 110, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 22,   to_port = 22 },
    { acl = "a", egress = false, rule_number = 120, protocol = "tcp",  cidr_block = "10.1.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "a", egress = false, rule_number = 130, protocol = "tcp",  cidr_block = "10.2.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "a", egress = false, rule_number = 140, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 1024, to_port = 65535 },
    { acl = "a", egress = false, rule_number = 150, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },
    # Outbound
    { acl = "a", egress = true,  rule_number = 100, protocol = "tcp",  cidr_block = "10.1.0.0/16", from_port = 22,   to_port = 22 },
    { acl = "a", egress = true,  rule_number = 110, protocol = "tcp",  cidr_block = "10.1.0.0/16", from_port = 80,   to_port = 80 },
    { acl = "a", egress = true,  rule_number = 111, protocol = "tcp",  cidr_block = "10.1.0.0/16", from_port = 443,  to_port = 443 },
    { acl = "a", egress = true,  rule_number = 120, protocol = "tcp",  cidr_block = "10.2.0.0/16", from_port = 443,  to_port = 443 },
    { acl = "a", egress = true,  rule_number = 121, protocol = "tcp",  cidr_block = "10.2.0.0/16", from_port = 8443, to_port = 8443 },
    { acl = "a", egress = true,  rule_number = 130, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 80,   to_port = 80 },
    { acl = "a", egress = true,  rule_number = 131, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 443,  to_port = 443 },
    { acl = "a", egress = true,  rule_number = 140, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 1024, to_port = 65535 },
    { acl = "a", egress = true,  rule_number = 150, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },

    # ── nacl "b_untrust" (subnet-b-untrust) ─────────────────────────────
    # Inbound
    { acl = "b_untrust", egress = false, rule_number = 100, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 443,  to_port = 443 },
    { acl = "b_untrust", egress = false, rule_number = 110, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 80,   to_port = 80 },
    { acl = "b_untrust", egress = false, rule_number = 120, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "b_untrust", egress = false, rule_number = 130, protocol = "tcp",  cidr_block = "10.3.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "b_untrust", egress = false, rule_number = 140, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 1024, to_port = 65535 },
    { acl = "b_untrust", egress = false, rule_number = 150, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },
    # Outbound
    { acl = "b_untrust", egress = true, rule_number = 100, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 1024, to_port = 65535 },
    { acl = "b_untrust", egress = true, rule_number = 110, protocol = "tcp",  cidr_block = "10.1.2.0/24", from_port = 443,  to_port = 443 },
    { acl = "b_untrust", egress = true, rule_number = 120, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 80,   to_port = 80 },
    { acl = "b_untrust", egress = true, rule_number = 121, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 443,  to_port = 443 },
    { acl = "b_untrust", egress = true, rule_number = 130, protocol = "tcp",  cidr_block = "10.3.0.0/16", from_port = 80,   to_port = 80 },
    { acl = "b_untrust", egress = true, rule_number = 131, protocol = "tcp",  cidr_block = "10.3.0.0/16", from_port = 443,  to_port = 443 },
    { acl = "b_untrust", egress = true, rule_number = 140, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },

    # ── nacl "b_trust" (subnet-b-trust) ─────────────────────────────────
    # Inbound
    { acl = "b_trust", egress = false, rule_number = 100, protocol = "tcp",  cidr_block = "10.1.1.0/24", from_port = 1024, to_port = 65535 },
    { acl = "b_trust", egress = false, rule_number = 110, protocol = "tcp",  cidr_block = "10.2.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "b_trust", egress = false, rule_number = 120, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "b_trust", egress = false, rule_number = 130, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },
    # Outbound
    { acl = "b_trust", egress = true, rule_number = 100, protocol = "tcp",  cidr_block = "10.2.0.0/16", from_port = 443,  to_port = 443 },
    { acl = "b_trust", egress = true, rule_number = 110, protocol = "tcp",  cidr_block = "10.1.1.0/24", from_port = 1024, to_port = 65535 },
    { acl = "b_trust", egress = true, rule_number = 120, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "b_trust", egress = true, rule_number = 130, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },

    # ── nacl "b_mgmt" (subnet-b-mgmt) ───────────────────────────────────
    # Inbound
    { acl = "b_mgmt", egress = false, rule_number = 100, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 22,   to_port = 22 },
    { acl = "b_mgmt", egress = false, rule_number = 110, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 443,  to_port = 443 },
    { acl = "b_mgmt", egress = false, rule_number = 120, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 1024, to_port = 65535 },
    { acl = "b_mgmt", egress = false, rule_number = 130, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },
    # Outbound
    { acl = "b_mgmt", egress = true, rule_number = 100, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "b_mgmt", egress = true, rule_number = 110, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 443,  to_port = 443 },
    { acl = "b_mgmt", egress = true, rule_number = 120, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },

    # ── nacl "c_dmz" (subnet-c-dmz) ─────────────────────────────────────
    # Inbound
    { acl = "c_dmz", egress = false, rule_number = 100, protocol = "tcp",  cidr_block = "10.1.2.0/24", from_port = 443,  to_port = 443 },
    { acl = "c_dmz", egress = false, rule_number = 110, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 443,  to_port = 443 },
    { acl = "c_dmz", egress = false, rule_number = 111, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 8443, to_port = 8443 },
    { acl = "c_dmz", egress = false, rule_number = 120, protocol = "tcp",  cidr_block = "10.2.2.0/24", from_port = 1024, to_port = 65535 },
    { acl = "c_dmz", egress = false, rule_number = 130, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },
    # Outbound
    { acl = "c_dmz", egress = true, rule_number = 100, protocol = "tcp",  cidr_block = "10.2.2.0/24", from_port = 443,  to_port = 443 },
    { acl = "c_dmz", egress = true, rule_number = 110, protocol = "tcp",  cidr_block = "10.1.2.0/24", from_port = 1024, to_port = 65535 },
    { acl = "c_dmz", egress = true, rule_number = 120, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "c_dmz", egress = true, rule_number = 130, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },

    # ── nacl "c_portal" (subnet-c-portal) ───────────────────────────────
    # Inbound
    { acl = "c_portal", egress = false, rule_number = 100, protocol = "tcp",  cidr_block = "10.2.1.0/24", from_port = 443,  to_port = 443 },
    { acl = "c_portal", egress = false, rule_number = 101, protocol = "tcp",  cidr_block = "10.2.1.0/24", from_port = 80,   to_port = 80 },
    { acl = "c_portal", egress = false, rule_number = 110, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 8443, to_port = 8443 },
    { acl = "c_portal", egress = false, rule_number = 120, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 1024, to_port = 65535 },
    { acl = "c_portal", egress = false, rule_number = 130, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },
    # Outbound
    { acl = "c_portal", egress = true, rule_number = 100, protocol = "tcp",  cidr_block = "10.2.1.0/24", from_port = 1024, to_port = 65535 },
    { acl = "c_portal", egress = true, rule_number = 110, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "c_portal", egress = true, rule_number = 120, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 443,  to_port = 443 },
    { acl = "c_portal", egress = true, rule_number = 130, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },

    # ── nacl "c_gateway" (subnet-c-gateway) ─────────────────────────────
    # Inbound
    { acl = "c_gateway", egress = false, rule_number = 100, protocol = "tcp",  cidr_block = "10.2.2.0/24", from_port = 443,   to_port = 443 },
    { acl = "c_gateway", egress = false, rule_number = 110, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 8443,  to_port = 8443 },
    { acl = "c_gateway", egress = false, rule_number = 111, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 444,   to_port = 444 },
    { acl = "c_gateway", egress = false, rule_number = 112, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 22,    to_port = 22 },
    { acl = "c_gateway", egress = false, rule_number = 120, protocol = "tcp",  cidr_block = "10.2.4.0/24", from_port = 0,     to_port = 65535 },
    { acl = "c_gateway", egress = false, rule_number = 130, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 1024,  to_port = 65535 },
    { acl = "c_gateway", egress = false, rule_number = 140, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,    to_port = -1 },
    # Outbound
    { acl = "c_gateway", egress = true, rule_number = 100, protocol = "tcp",  cidr_block = "10.2.2.0/24", from_port = 1024, to_port = 65535 },
    { acl = "c_gateway", egress = true, rule_number = 110, protocol = "tcp",  cidr_block = "10.2.4.0/24", from_port = 444,  to_port = 444 },
    { acl = "c_gateway", egress = true, rule_number = 111, protocol = "tcp",  cidr_block = "10.2.4.0/24", from_port = 8443, to_port = 8443 },
    { acl = "c_gateway", egress = true, rule_number = 120, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 443,  to_port = 443 },
    { acl = "c_gateway", egress = true, rule_number = 130, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "c_gateway", egress = true, rule_number = 140, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },

    # ── nacl "c_controller" (subnet-c-controller) ───────────────────────
    # Inbound
    { acl = "c_controller", egress = false, rule_number = 100, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 8443, to_port = 8443 },
    { acl = "c_controller", egress = false, rule_number = 101, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 444,  to_port = 444 },
    { acl = "c_controller", egress = false, rule_number = 102, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 22,   to_port = 22 },
    { acl = "c_controller", egress = false, rule_number = 110, protocol = "tcp",  cidr_block = "10.2.2.0/24", from_port = 444,  to_port = 444 },
    { acl = "c_controller", egress = false, rule_number = 111, protocol = "tcp",  cidr_block = "10.2.2.0/24", from_port = 8443, to_port = 8443 },
    { acl = "c_controller", egress = false, rule_number = 120, protocol = "tcp",  cidr_block = "10.2.3.0/24", from_port = 444,  to_port = 444 },
    { acl = "c_controller", egress = false, rule_number = 121, protocol = "tcp",  cidr_block = "10.2.3.0/24", from_port = 8443, to_port = 8443 },
    { acl = "c_controller", egress = false, rule_number = 130, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 1024, to_port = 65535 },
    { acl = "c_controller", egress = false, rule_number = 140, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },
    # Outbound
    { acl = "c_controller", egress = true, rule_number = 100, protocol = "tcp",  cidr_block = "10.2.2.0/24", from_port = 1024, to_port = 65535 },
    { acl = "c_controller", egress = true, rule_number = 110, protocol = "tcp",  cidr_block = "10.2.3.0/24", from_port = 1024, to_port = 65535 },
    { acl = "c_controller", egress = true, rule_number = 120, protocol = "tcp",  cidr_block = "10.0.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "c_controller", egress = true, rule_number = 130, protocol = "tcp",  cidr_block = "0.0.0.0/0",   from_port = 443,  to_port = 443 },
    { acl = "c_controller", egress = true, rule_number = 140, protocol = "icmp", cidr_block = "10.0.0.0/8",  from_port = -1,   to_port = -1 },

    # ── nacl "d" (subnet-d-private) ─────────────────────────────────────
    # Inbound
    { acl = "d", egress = false, rule_number = 100, protocol = "tcp",  cidr_block = "10.1.0.0/16", from_port = 22,   to_port = 22 },
    { acl = "d", egress = false, rule_number = 110, protocol = "tcp",  cidr_block = "10.1.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "d", egress = false, rule_number = 120, protocol = "tcp",  cidr_block = "10.2.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "d", egress = false, rule_number = 130, protocol = "icmp", cidr_block = "10.1.0.0/16", from_port = -1,   to_port = -1 },
    # Outbound
    { acl = "d", egress = true, rule_number = 100, protocol = "tcp",  cidr_block = "10.1.0.0/16", from_port = 80,   to_port = 80 },
    { acl = "d", egress = true, rule_number = 101, protocol = "tcp",  cidr_block = "10.1.0.0/16", from_port = 443,  to_port = 443 },
    { acl = "d", egress = true, rule_number = 110, protocol = "tcp",  cidr_block = "10.2.0.0/16", from_port = 443,  to_port = 443 },
    { acl = "d", egress = true, rule_number = 120, protocol = "tcp",  cidr_block = "10.1.0.0/16", from_port = 1024, to_port = 65535 },
    { acl = "d", egress = true, rule_number = 130, protocol = "icmp", cidr_block = "10.1.0.0/16", from_port = -1,   to_port = -1 },
  ]

  nacl_rule_map = {
    for rule in local.nacl_rules :
    "${rule.acl}-${rule.egress ? "egress" : "ingress"}-${rule.rule_number}" => rule
  }
}

# ============================================================
# VPCs
# ============================================================

resource "aws_vpc" "this" {
  for_each = local.vpcs

  cidr_block           = each.value.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name       = each.value.name
      LabRole    = upper(each.key)
      ManagedBy  = "terraform"
      Deployment = var.name_prefix
    }
  )
}

# ============================================================
# Subnets
# ============================================================

resource "aws_subnet" "this" {
  for_each = local.subnets

  availability_zone       = local.selected_az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.this[each.value.vpc_key].id

  tags = merge(var.tags, { Name = each.value.name })
}

# ============================================================
# Internet Gateways (VPC-A and VPC-B)
# ============================================================

resource "aws_internet_gateway" "this" {
  for_each = {
    a = local.vpcs.a
    b = local.vpcs.b
  }

  vpc_id = aws_vpc.this[each.key].id

  tags = merge(var.tags, { Name = "lab-igw-vpc-${each.key}" })
}

# ============================================================
# NAT Gateway + EIP (centralized egress in subnet-a-public)
# ============================================================

resource "aws_eip" "nat_gw" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this["a"]]
  tags       = merge(var.tags, { Name = "lab-eip-nat-gw-vpc-a" })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat_gw.id
  subnet_id     = aws_subnet.this["a"].id
  depends_on    = [aws_internet_gateway.this["a"]]
  tags          = merge(var.tags, { Name = "nat-gw-vpc-a-centralized-egress" })
}

# ============================================================
# Route Tables (one per subnet)
# ============================================================

resource "aws_route_table" "this" {
  for_each = local.subnets

  vpc_id = aws_vpc.this[each.value.vpc_key].id

  tags = merge(var.tags, { Name = "lab-rt-${replace(each.key, "_", "-")}" })
}

resource "aws_route_table_association" "this" {
  for_each = local.subnets

  route_table_id = aws_route_table.this[each.key].id
  subnet_id      = aws_subnet.this[each.key].id
}

resource "aws_route" "this" {
  for_each = local.route_entries

  destination_cidr_block = each.value.destination
  route_table_id         = aws_route_table.this[each.value.subnet].id
  gateway_id             = each.value.igw != null ? aws_internet_gateway.this[each.value.igw].id : null
  transit_gateway_id     = each.value.tgw != null ? aws_ec2_transit_gateway.this[each.value.tgw].id : null

  depends_on = [
    aws_internet_gateway.this,
    aws_ec2_transit_gateway_vpc_attachment.this,
  ]
}

# ============================================================
# Transit Gateways
# ============================================================

resource "aws_ec2_transit_gateway" "this" {
  for_each = local.transit_gateways

  amazon_side_asn                    = each.value.amazon_side_asn
  auto_accept_shared_attachments     = "disable"
  default_route_table_association    = "disable"
  default_route_table_propagation    = "disable"
  dns_support                        = "enable"
  multicast_support                  = "disable"
  security_group_referencing_support = "disable"
  vpn_ecmp_support                   = "enable"

  tags = merge(var.tags, { Name = each.value.name })
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = local.transit_gateways

  transit_gateway_id = aws_ec2_transit_gateway.this[each.key].id

  tags = merge(var.tags, { Name = each.value.route_table })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = local.attachment_definitions

  subnet_ids                                      = [aws_subnet.this[each.value.subnet].id]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  transit_gateway_id                              = aws_ec2_transit_gateway.this[each.value.tgw_key].id
  vpc_id                                          = aws_vpc.this[each.value.vpc_key].id

  tags = merge(var.tags, { Name = each.value.name })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = local.tgw_associations

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment_key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
}

resource "aws_ec2_transit_gateway_route" "this" {
  for_each = local.tgw_route_entries

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment_key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id

  depends_on = [aws_ec2_transit_gateway_route_table_association.this]
}

# ============================================================
# Network ACLs (one per subnet)
# ============================================================

resource "aws_network_acl" "this" {
  for_each = local.subnets

  vpc_id     = aws_vpc.this[local.subnets[each.key].vpc_key].id
  subnet_ids = [aws_subnet.this[each.key].id]

  tags = merge(var.tags, { Name = "nacl-${replace(each.key, "_", "-")}" })
}

resource "aws_network_acl_rule" "this" {
  for_each = local.nacl_rule_map

  cidr_block     = each.value.cidr_block
  egress         = each.value.egress
  from_port      = each.value.protocol == "icmp" ? null : each.value.from_port
  icmp_code      = each.value.protocol == "icmp" ? each.value.to_port : null
  icmp_type      = each.value.protocol == "icmp" ? each.value.from_port : null
  network_acl_id = aws_network_acl.this[each.value.acl].id
  protocol       = each.value.protocol
  rule_action    = "allow"
  rule_number    = each.value.rule_number
  to_port        = each.value.protocol == "icmp" ? null : each.value.to_port
}

# ============================================================
# VPC Flow Logs (VPC-A)
# ============================================================

resource "aws_cloudwatch_log_group" "vpc_a_flow_logs" {
  name              = "/aws/vpc/flow-logs/vpc-a"
  retention_in_days = 90
  tags              = merge(var.tags, { Name = "lab-flow-logs-vpc-a" })
}

resource "aws_iam_role" "flow_log" {
  name = "lab-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, { Name = "lab-flow-log-role" })
}

resource "aws_iam_role_policy" "flow_log" {
  name = "lab-flow-log-policy"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "vpc_a" {
  vpc_id          = aws_vpc.this["a"].id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_a_flow_logs.arn
  tags            = merge(var.tags, { Name = "flow-log-vpc-a-billing-sla" })
}

# ============================================================
# TLS Self-Signed Certificate + ACM (for ALB)
# ============================================================

resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem

  subject {
    common_name  = "lab.internal"
    organization = "TGW Lab"
  }

  validity_period_hours = 8760
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_acm_certificate" "alb" {
  private_key      = tls_private_key.alb.private_key_pem
  certificate_body = tls_self_signed_cert.alb.cert_pem
  tags             = merge(var.tags, { Name = "lab-acm-alb-self-signed" })
}

# ============================================================
# ALB (internet-facing, VPC-B subnet-b-untrust)
# ============================================================

resource "aws_lb" "alb" {
  name               = "lab-alb-customer-entry"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = [aws_subnet.this["b_untrust"].id]
  tags               = merge(var.tags, { Name = "lab-alb-customer-entry" })
}

resource "aws_lb_target_group" "alb" {
  name        = "lab-alb-tg-palo-untrust"
  port        = 443
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = aws_vpc.this["b"].id

  health_check {
    protocol = "HTTPS"
    path     = "/"
    matcher  = "200-499"
  }

  tags = merge(var.tags, { Name = "lab-alb-tg-palo-untrust" })
}

resource "aws_lb_target_group_attachment" "alb" {
  target_group_arn = aws_lb_target_group.alb.arn
  target_id        = "10.1.1.10"
  port             = 443
}

resource "aws_lb_listener" "alb_https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }
}

resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ============================================================
# NLB-B (internal, VPC-B — Palo Alto trust interface)
# ============================================================

resource "aws_lb" "nlb_b" {
  name               = "lab-nlb-b-palo-trust"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.this["b_untrust"].id]
  tags               = merge(var.tags, { Name = "lab-nlb-b-palo-trust" })
}

resource "aws_lb_target_group" "nlb_b_80" {
  name        = "lab-nlb-b-palo-trust-80"
  port        = 80
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.this["b"].id
  tags        = merge(var.tags, { Name = "lab-nlb-b-palo-trust-80" })
}

resource "aws_lb_target_group_attachment" "nlb_b_80" {
  target_group_arn = aws_lb_target_group.nlb_b_80.arn
  target_id        = "10.1.2.10"
  port             = 80
}

resource "aws_lb_target_group" "nlb_b_443" {
  name        = "lab-nlb-b-palo-trust-443"
  port        = 443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.this["b"].id
  tags        = merge(var.tags, { Name = "lab-nlb-b-palo-trust-443" })
}

resource "aws_lb_target_group_attachment" "nlb_b_443" {
  target_group_arn = aws_lb_target_group.nlb_b_443.arn
  target_id        = "10.1.2.10"
  port             = 443
}

resource "aws_lb_listener" "nlb_b_80" {
  load_balancer_arn = aws_lb.nlb_b.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_b_80.arn
  }
}

resource "aws_lb_listener" "nlb_b_443" {
  load_balancer_arn = aws_lb.nlb_b.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_b_443.arn
  }
}

# ============================================================
# NLB-C (internal, VPC-C — AppGate portal)
# ============================================================

resource "aws_lb" "nlb_c" {
  name               = "lab-nlb-c-appgate-portal"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.this["c_dmz"].id]
  tags               = merge(var.tags, { Name = "lab-nlb-c-appgate-portal" })
}

resource "aws_lb_target_group" "nlb_c_80" {
  name        = "lab-nlb-c-appgate-portal-80"
  port        = 80
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.this["c"].id
  tags        = merge(var.tags, { Name = "lab-nlb-c-appgate-portal-80" })
}

resource "aws_lb_target_group_attachment" "nlb_c_80" {
  target_group_arn = aws_lb_target_group.nlb_c_80.arn
  target_id        = "10.2.2.10"
  port             = 80
}

resource "aws_lb_target_group" "nlb_c_443" {
  name        = "lab-nlb-c-appgate-portal-443"
  port        = 443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.this["c"].id
  tags        = merge(var.tags, { Name = "lab-nlb-c-appgate-portal-443" })
}

resource "aws_lb_target_group_attachment" "nlb_c_443" {
  target_group_arn = aws_lb_target_group.nlb_c_443.arn
  target_id        = "10.2.2.10"
  port             = 443
}

resource "aws_lb_listener" "nlb_c_80" {
  load_balancer_arn = aws_lb.nlb_c.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_c_80.arn
  }
}

resource "aws_lb_listener" "nlb_c_443" {
  load_balancer_arn = aws_lb.nlb_c.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_c_443.arn
  }
}
