# Model 2+3 CLI spike imports and state cleanup.

removed {
  from = module.network.aws_ec2_transit_gateway_route_table_association.this

  lifecycle {
    destroy = false
  }
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table.tgw1_spoke
  id = "tgw-rtb-048b1f202b58aa953"
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table.tgw1_firewall
  id = "tgw-rtb-0b4ef7ed52e24e8fb"
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table.tgw2_spoke
  id = "tgw-rtb-08aff34bbf46e3e04"
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table.tgw2_firewall
  id = "tgw-rtb-064e2f1575529422b"
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table_association.tgw1_vpc_a_spoke
  id = "tgw-rtb-048b1f202b58aa953_tgw-attach-0add575b2d88438f6"
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table_association.tgw1_vpc_c_spoke
  id = "tgw-rtb-048b1f202b58aa953_tgw-attach-0fba819a08552a4cb"
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table_association.tgw1_vpc_b_firewall
  id = "tgw-rtb-0b4ef7ed52e24e8fb_tgw-attach-066fd221541a5125a"
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table_association.tgw2_vpc_d_spoke
  id = "tgw-rtb-08aff34bbf46e3e04_tgw-attach-002e2a419574cdc3c"
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table_association.tgw2_vpc_c_spoke
  id = "tgw-rtb-08aff34bbf46e3e04_tgw-attach-0989e560b674e039c"
}

import {
  to = module.network.aws_ec2_transit_gateway_route_table_association.tgw2_vpc_b_firewall
  id = "tgw-rtb-064e2f1575529422b_tgw-attach-08c236efde613922b"
}

import {
  to = module.network.aws_ec2_transit_gateway_route.tgw1_spoke_default
  id = "tgw-rtb-048b1f202b58aa953_0.0.0.0/0"
}

import {
  to = module.network.aws_ec2_transit_gateway_route.tgw1_fw_default
  id = "tgw-rtb-0b4ef7ed52e24e8fb_0.0.0.0/0"
}

import {
  to = module.network.aws_ec2_transit_gateway_route.tgw1_fw_vpc_a
  id = "tgw-rtb-0b4ef7ed52e24e8fb_10.0.0.0/16"
}

import {
  to = module.network.aws_ec2_transit_gateway_route.tgw1_fw_vpc_c
  id = "tgw-rtb-0b4ef7ed52e24e8fb_10.2.0.0/16"
}

import {
  to = module.network.aws_ec2_transit_gateway_route.tgw2_spoke_default
  id = "tgw-rtb-08aff34bbf46e3e04_0.0.0.0/0"
}

import {
  to = module.network.aws_ec2_transit_gateway_route.tgw2_fw_default
  id = "tgw-rtb-064e2f1575529422b_0.0.0.0/0"
}

import {
  to = module.network.aws_ec2_transit_gateway_route.tgw2_fw_vpc_b
  id = "tgw-rtb-064e2f1575529422b_10.1.0.0/16"
}

import {
  to = module.network.aws_ec2_transit_gateway_route.tgw2_fw_vpc_c
  id = "tgw-rtb-064e2f1575529422b_10.2.0.0/16"
}

import {
  to = module.network.aws_ec2_transit_gateway_route.tgw2_fw_vpc_d
  id = "tgw-rtb-064e2f1575529422b_10.3.0.0/16"
}

import {
  to = module.network.aws_network_acl_rule.this["b_trust-ingress-92"]
  id = "acl-0695ef7e0e0b31db2:92:tcp:false"
}

import {
  to = module.network.aws_network_acl_rule.this["b_trust-egress-101"]
  id = "acl-0695ef7e0e0b31db2:101:tcp:true"
}

import {
  to = module.network.aws_network_acl_rule.this["c_dmz-ingress-99"]
  id = "acl-045e906a514372224:99:tcp:false"
}

import {
  to = module.network.aws_network_acl_rule.this["c_portal-ingress-93"]
  id = "acl-0c461e7c980d08c00:93:tcp:false"
}

import {
  to = module.network.aws_network_acl_rule.this["c_portal-ingress-94"]
  id = "acl-0c461e7c980d08c00:94:tcp:false"
}

import {
  to = module.network.aws_network_acl_rule.this["c_portal-egress-89"]
  id = "acl-0c461e7c980d08c00:89:tcp:true"
}
