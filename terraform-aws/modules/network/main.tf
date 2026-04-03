data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_az = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])

  vpcs = {
    a = {
      cidr = "10.0.0.0/16"
      name = "lab-vpc-a-cloudhost"
    }
    b = {
      cidr = "10.1.0.0/16"
      name = "lab-vpc-b-paloalto"
    }
    c = {
      cidr = "10.2.0.0/16"
      name = "lab-vpc-c-appgate"
    }
    d = {
      cidr = "10.3.0.0/16"
      name = "lab-vpc-d-customer"
    }
  }

  subnets = {
    a = {
      cidr    = "10.0.1.0/24"
      name    = "lab-subnet-a"
      vpc_key = "a"
    }
    b = {
      cidr    = "10.1.1.0/24"
      name    = "lab-subnet-b"
      vpc_key = "b"
    }
    c = {
      cidr    = "10.2.1.0/24"
      name    = "lab-subnet-c"
      vpc_key = "c"
    }
    d = {
      cidr    = "10.3.1.0/24"
      name    = "lab-subnet-d"
      vpc_key = "d"
    }
  }

  transit_gateways = {
    tgw1 = {
      amazon_side_asn = 64512
      name            = "lab-tgw1-mgmt"
      route_table     = "tgw1-rt-mgmt"
    }
    tgw2 = {
      amazon_side_asn = 64513
      name            = "lab-tgw2-customer"
      route_table     = "tgw2-rt-customer"
    }
  }

  attachment_definitions = {
    tgw1_a = {
      name    = "tgw1-attach-vpc-a"
      subnet  = "a"
      tgw_key = "tgw1"
      vpc_key = "a"
    }
    tgw1_b = {
      name    = "tgw1-attach-vpc-b"
      subnet  = "b"
      tgw_key = "tgw1"
      vpc_key = "b"
    }
    tgw1_c = {
      name    = "tgw1-attach-vpc-c"
      subnet  = "c"
      tgw_key = "tgw1"
      vpc_key = "c"
    }
    tgw2_b = {
      name    = "tgw2-attach-vpc-b"
      subnet  = "b"
      tgw_key = "tgw2"
      vpc_key = "b"
    }
    tgw2_c = {
      name    = "tgw2-attach-vpc-c"
      subnet  = "c"
      tgw_key = "tgw2"
      vpc_key = "c"
    }
    tgw2_d = {
      name    = "tgw2-attach-vpc-d"
      subnet  = "d"
      tgw_key = "tgw2"
      vpc_key = "d"
    }
  }

  route_entries = {
    a_internet = {
      destination     = "0.0.0.0/0"
      gateway_vpc     = "a"
      route_table_vpc = "a"
    }
    a_to_b = {
      destination     = local.vpcs.b.cidr
      route_table_vpc = "a"
      tgw_key         = "tgw1"
    }
    a_to_c = {
      destination     = local.vpcs.c.cidr
      route_table_vpc = "a"
      tgw_key         = "tgw1"
    }
    b_to_a = {
      destination     = local.vpcs.a.cidr
      route_table_vpc = "b"
      tgw_key         = "tgw1"
    }
    b_to_c = {
      destination     = local.vpcs.c.cidr
      route_table_vpc = "b"
      tgw_key         = "tgw1"
    }
    b_to_d = {
      destination     = local.vpcs.d.cidr
      route_table_vpc = "b"
      tgw_key         = "tgw2"
    }
    c_to_a = {
      destination     = local.vpcs.a.cidr
      route_table_vpc = "c"
      tgw_key         = "tgw1"
    }
    c_to_b = {
      destination     = local.vpcs.b.cidr
      route_table_vpc = "c"
      tgw_key         = "tgw1"
    }
    c_to_d = {
      destination     = local.vpcs.d.cidr
      route_table_vpc = "c"
      tgw_key         = "tgw2"
    }
    d_to_b = {
      destination     = local.vpcs.b.cidr
      route_table_vpc = "d"
      tgw_key         = "tgw2"
    }
    d_to_c = {
      destination     = local.vpcs.c.cidr
      route_table_vpc = "d"
      tgw_key         = "tgw2"
    }
  }

  tgw_route_entries = {
    tgw1_a = {
      attachment_key = "tgw1_a"
      cidr           = local.vpcs.a.cidr
      route_table    = "tgw1"
    }
    tgw1_b = {
      attachment_key = "tgw1_b"
      cidr           = local.vpcs.b.cidr
      route_table    = "tgw1"
    }
    tgw1_c = {
      attachment_key = "tgw1_c"
      cidr           = local.vpcs.c.cidr
      route_table    = "tgw1"
    }
    tgw2_b = {
      attachment_key = "tgw2_b"
      cidr           = local.vpcs.b.cidr
      route_table    = "tgw2"
    }
    tgw2_c = {
      attachment_key = "tgw2_c"
      cidr           = local.vpcs.c.cidr
      route_table    = "tgw2"
    }
    tgw2_d = {
      attachment_key = "tgw2_d"
      cidr           = local.vpcs.d.cidr
      route_table    = "tgw2"
    }
  }

  tgw_associations = {
    tgw1_a = {
      attachment_key = "tgw1_a"
      route_table    = "tgw1"
    }
    tgw1_b = {
      attachment_key = "tgw1_b"
      route_table    = "tgw1"
    }
    tgw1_c = {
      attachment_key = "tgw1_c"
      route_table    = "tgw1"
    }
    tgw2_b = {
      attachment_key = "tgw2_b"
      route_table    = "tgw2"
    }
    tgw2_c = {
      attachment_key = "tgw2_c"
      route_table    = "tgw2"
    }
    tgw2_d = {
      attachment_key = "tgw2_d"
      route_table    = "tgw2"
    }
  }

  nacl_rules = concat(
    [for index, cidr in var.management_cidrs : {
      acl         = "a"
      cidr_block  = cidr
      egress      = false
      from_port   = 22
      protocol    = "tcp"
      rule_number = 100 + index
      to_port     = 22
    }],
    [for index, cidr in var.management_cidrs : {
      acl         = "a"
      cidr_block  = cidr
      egress      = false
      from_port   = 3389
      protocol    = "tcp"
      rule_number = 120 + index
      to_port     = 3389
    }],
    [for index, cidr in var.management_cidrs : {
      acl         = "a"
      cidr_block  = cidr
      egress      = true
      from_port   = 1024
      protocol    = "tcp"
      rule_number = 100 + index
      to_port     = 65535
    }],
    [
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 22
        protocol    = "tcp"
        rule_number = 150
        to_port     = 22
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 151
        to_port     = 80
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 152
        to_port     = 65535
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 153
        to_port     = -1
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 8
        protocol    = "icmp"
        rule_number = 154
        to_port     = 0
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = true
        from_port   = 22
        protocol    = "tcp"
        rule_number = 150
        to_port     = 22
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 151
        to_port     = 80
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 152
        to_port     = 65535
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 153
        to_port     = -1
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.a.cidr
        egress      = true
        from_port   = 8
        protocol    = "icmp"
        rule_number = 154
        to_port     = 0
      },
      {
        acl         = "a"
        cidr_block  = "0.0.0.0/0"
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 200
        to_port     = 65535
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 210
        to_port     = 65535
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 220
        to_port     = 65535
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 230
        to_port     = -1
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 240
        to_port     = -1
      },
      {
        acl         = "a"
        cidr_block  = "0.0.0.0/0"
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 200
        to_port     = 80
      },
      {
        acl         = "a"
        cidr_block  = "0.0.0.0/0"
        egress      = true
        from_port   = 443
        protocol    = "tcp"
        rule_number = 210
        to_port     = 443
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 22
        protocol    = "tcp"
        rule_number = 220
        to_port     = 22
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 22
        protocol    = "tcp"
        rule_number = 230
        to_port     = 22
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 240
        to_port     = 80
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 250
        to_port     = 80
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 260
        to_port     = -1
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 8
        protocol    = "icmp"
        rule_number = 261
        to_port     = 0
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 270
        to_port     = -1
      },
      {
        acl         = "a"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 8
        protocol    = "icmp"
        rule_number = 271
        to_port     = 0
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 22
        protocol    = "tcp"
        rule_number = 90
        to_port     = 22
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 91
        to_port     = 80
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 92
        to_port     = 65535
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 93
        to_port     = -1
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 8
        protocol    = "icmp"
        rule_number = 94
        to_port     = 0
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 22
        protocol    = "tcp"
        rule_number = 100
        to_port     = 22
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 110
        to_port     = 80
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 120
        to_port     = 80
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = 22
        protocol    = "tcp"
        rule_number = 130
        to_port     = 22
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 140
        to_port     = 80
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 150
        to_port     = 65535
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 160
        to_port     = 65535
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 170
        to_port     = -1
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 8
        protocol    = "icmp"
        rule_number = 171
        to_port     = 0
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 180
        to_port     = -1
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 190
        to_port     = -1
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 22
        protocol    = "tcp"
        rule_number = 90
        to_port     = 22
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 91
        to_port     = 80
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 92
        to_port     = 65535
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 93
        to_port     = -1
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 8
        protocol    = "icmp"
        rule_number = 94
        to_port     = 0
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.a.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 100
        to_port     = 65535
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = 22
        protocol    = "tcp"
        rule_number = 110
        to_port     = 22
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 120
        to_port     = 65535
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 22
        protocol    = "tcp"
        rule_number = 130
        to_port     = 22
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 140
        to_port     = 80
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 150
        to_port     = 65535
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.a.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 160
        to_port     = -1
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 170
        to_port     = -1
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = 8
        protocol    = "icmp"
        rule_number = 171
        to_port     = 0
      },
      {
        acl         = "b"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 180
        to_port     = -1
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = 22
        protocol    = "tcp"
        rule_number = 90
        to_port     = 22
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 91
        to_port     = 80
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 92
        to_port     = 65535
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 93
        to_port     = -1
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = 8
        protocol    = "icmp"
        rule_number = 94
        to_port     = 0
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 22
        protocol    = "tcp"
        rule_number = 100
        to_port     = 22
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 110
        to_port     = 80
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 120
        to_port     = 80
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 22
        protocol    = "tcp"
        rule_number = 130
        to_port     = 22
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 140
        to_port     = 80
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 150
        to_port     = 65535
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 160
        to_port     = 65535
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 170
        to_port     = -1
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.a.cidr
        egress      = false
        from_port   = 8
        protocol    = "icmp"
        rule_number = 171
        to_port     = 0
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 180
        to_port     = -1
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 190
        to_port     = -1
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 22
        protocol    = "tcp"
        rule_number = 90
        to_port     = 22
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 91
        to_port     = 80
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 92
        to_port     = 65535
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 93
        to_port     = -1
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 8
        protocol    = "icmp"
        rule_number = 94
        to_port     = 0
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.a.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 100
        to_port     = 65535
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 22
        protocol    = "tcp"
        rule_number = 110
        to_port     = 22
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 120
        to_port     = 80
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 130
        to_port     = 65535
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 140
        to_port     = 65535
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.a.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 150
        to_port     = -1
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 160
        to_port     = -1
      },
      {
        acl         = "c"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 170
        to_port     = -1
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = 22
        protocol    = "tcp"
        rule_number = 90
        to_port     = 22
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = 80
        protocol    = "tcp"
        rule_number = 91
        to_port     = 80
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 92
        to_port     = 65535
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 93
        to_port     = -1
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = false
        from_port   = 8
        protocol    = "icmp"
        rule_number = 94
        to_port     = 0
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 22
        protocol    = "tcp"
        rule_number = 100
        to_port     = 22
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 110
        to_port     = 65535
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.c.cidr
        egress      = false
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 120
        to_port     = 65535
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = -1
        protocol    = "icmp"
        rule_number = 130
        to_port     = -1
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.b.cidr
        egress      = false
        from_port   = 8
        protocol    = "icmp"
        rule_number = 131
        to_port     = 0
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = 22
        protocol    = "tcp"
        rule_number = 90
        to_port     = 22
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 91
        to_port     = 80
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 92
        to_port     = 65535
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 93
        to_port     = -1
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.d.cidr
        egress      = true
        from_port   = 8
        protocol    = "icmp"
        rule_number = 94
        to_port     = 0
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 100
        to_port     = 80
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = 80
        protocol    = "tcp"
        rule_number = 110
        to_port     = 80
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = 1024
        protocol    = "tcp"
        rule_number = 120
        to_port     = 65535
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.b.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 130
        to_port     = -1
      },
      {
        acl         = "d"
        cidr_block  = local.vpcs.c.cidr
        egress      = true
        from_port   = -1
        protocol    = "icmp"
        rule_number = 140
        to_port     = -1
      }
    ]
  )

  nacl_rule_map = {
    for rule in local.nacl_rules :
    "${rule.acl}-${rule.egress ? "egress" : "ingress"}-${rule.rule_number}" => rule
  }
}

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

resource "aws_internet_gateway" "this" {
  for_each = {
    a = local.vpcs.a
  }

  vpc_id = aws_vpc.this[each.key].id

  tags = merge(
    var.tags,
    {
      Name = "lab-igw-vpc-a"
    }
  )
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  availability_zone       = local.selected_az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.this[each.value.vpc_key].id

  tags = merge(
    var.tags,
    {
      Name = each.value.name
    }
  )
}

resource "aws_route_table" "this" {
  for_each = local.vpcs

  vpc_id = aws_vpc.this[each.key].id

  tags = merge(
    var.tags,
    {
      Name = "lab-rt-vpc-${each.key}"
    }
  )
}

resource "aws_route_table_association" "this" {
  for_each = local.subnets

  route_table_id = aws_route_table.this[each.value.vpc_key].id
  subnet_id      = aws_subnet.this[each.key].id
}

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

  tags = merge(
    var.tags,
    {
      Name = each.value.name
    }
  )
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = local.transit_gateways

  transit_gateway_id = aws_ec2_transit_gateway.this[each.key].id

  tags = merge(
    var.tags,
    {
      Name = each.value.route_table
    }
  )
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = local.attachment_definitions

  subnet_ids                                      = [aws_subnet.this[each.value.subnet].id]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  transit_gateway_id                              = aws_ec2_transit_gateway.this[each.value.tgw_key].id
  vpc_id                                          = aws_vpc.this[each.value.vpc_key].id

  tags = merge(
    var.tags,
    {
      Name = each.value.name
    }
  )
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

resource "aws_route" "this" {
  for_each = local.route_entries

  destination_cidr_block = each.value.destination
  route_table_id         = aws_route_table.this[each.value.route_table_vpc].id
  gateway_id             = try(aws_internet_gateway.this[each.value.gateway_vpc].id, null)
  transit_gateway_id     = try(aws_ec2_transit_gateway.this[each.value.tgw_key].id, null)

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_network_acl" "this" {
  for_each = local.vpcs

  subnet_ids = [aws_subnet.this[each.key].id]
  vpc_id     = aws_vpc.this[each.key].id

  tags = merge(
    var.tags,
    {
      Name = "nacl-vpc-${each.key}"
    }
  )
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
