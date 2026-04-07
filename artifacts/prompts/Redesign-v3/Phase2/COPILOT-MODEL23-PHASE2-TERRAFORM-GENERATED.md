# Copilot Prompt — Model 2+3 Phase 2 Terraform Codification
# Generated from CLI spike session 2025-07-14
# DO NOT EDIT resource IDs — they are the actual live values from the spike

---

## YOUR ROLE

You are codifying a live AWS architecture change into Terraform.
The CLI spike has already been run and validated. Your job is to make
Terraform match what is running, not to design or change the architecture.

Do NOT run terraform apply. Do NOT modify any VPCs, TGWs, or attachments.
Your output is a reviewed, validated plan ready for operator apply.

---

## READ THESE FILES FIRST

1. artifacts\skills\terraform-skill.md
2. artifacts\results\model23-cli-spike-20250714.md
3. terraform-aws\modules\network\main.tf

After reading, confirm you understand:
- What resources were created via CLI
- What resources were modified via CLI
- What the Terraform module currently contains
- What needs to be imported vs what needs new resource blocks

---

## WHAT WAS BUILT VIA CLI (2025-07-14)

### New TGW Route Tables (must be imported)
| Terraform Resource Name | ID |
|---|---|
| aws_ec2_transit_gateway_route_table.tgw1_spoke | tgw-rtb-048b1f202b58aa953 |
| aws_ec2_transit_gateway_route_table.tgw1_firewall | tgw-rtb-0b4ef7ed52e24e8fb |
| aws_ec2_transit_gateway_route_table.tgw2_spoke | tgw-rtb-08aff34bbf46e3e04 |
| aws_ec2_transit_gateway_route_table.tgw2_firewall | tgw-rtb-064e2f1575529422b |

### Appliance Mode (modify existing attachment resources)
| Attachment | ID | New Value |
|---|---|---|
| tgw1-attach-vpc-b | tgw-attach-066fd221541a5125a | appliance_mode_support = "enable" |
| tgw2-attach-vpc-b | tgw-attach-08c236efde613922b | appliance_mode_support = "enable" |

### New Associations (must be imported)
| Terraform Resource Name | Attachment ID | RT ID |
|---|---|---|
| aws_ec2_transit_gateway_route_table_association.tgw1_vpc_a_spoke | tgw-attach-0add575b2d88438f6 | tgw-rtb-048b1f202b58aa953 |
| aws_ec2_transit_gateway_route_table_association.tgw1_vpc_c_spoke | tgw-attach-0fba819a08552a4cb | tgw-rtb-048b1f202b58aa953 |
| aws_ec2_transit_gateway_route_table_association.tgw1_vpc_b_firewall | tgw-attach-066fd221541a5125a | tgw-rtb-0b4ef7ed52e24e8fb |
| aws_ec2_transit_gateway_route_table_association.tgw2_vpc_d_spoke | tgw-attach-002e2a419574cdc3c | tgw-rtb-08aff34bbf46e3e04 |
| aws_ec2_transit_gateway_route_table_association.tgw2_vpc_c_spoke | tgw-attach-0989e560b674e039c | tgw-rtb-08aff34bbf46e3e04 |
| aws_ec2_transit_gateway_route_table_association.tgw2_vpc_b_firewall | tgw-attach-08c236efde613922b | tgw-rtb-064e2f1575529422b |

### New TGW Routes (must be imported)
Import ID format: <route-table-id>_<cidr>

**tgw1-rt-spoke**
| Terraform Resource Name | RT ID | CIDR | Attachment |
|---|---|---|---|
| aws_ec2_transit_gateway_route.tgw1_spoke_default | tgw-rtb-048b1f202b58aa953 | 0.0.0.0/0 | tgw-attach-066fd221541a5125a |

**tgw1-rt-firewall**
| Terraform Resource Name | RT ID | CIDR | Attachment |
|---|---|---|---|
| aws_ec2_transit_gateway_route.tgw1_fw_default | tgw-rtb-0b4ef7ed52e24e8fb | 0.0.0.0/0 | tgw-attach-0add575b2d88438f6 |
| aws_ec2_transit_gateway_route.tgw1_fw_vpc_a | tgw-rtb-0b4ef7ed52e24e8fb | 10.0.0.0/16 | tgw-attach-0add575b2d88438f6 |
| aws_ec2_transit_gateway_route.tgw1_fw_vpc_c | tgw-rtb-0b4ef7ed52e24e8fb | 10.2.0.0/16 | tgw-attach-0fba819a08552a4cb |

**tgw2-rt-spoke**
| Terraform Resource Name | RT ID | CIDR | Attachment |
|---|---|---|---|
| aws_ec2_transit_gateway_route.tgw2_spoke_default | tgw-rtb-08aff34bbf46e3e04 | 0.0.0.0/0 | tgw-attach-08c236efde613922b |

**tgw2-rt-firewall**
| Terraform Resource Name | RT ID | CIDR | Attachment |
|---|---|---|---|
| aws_ec2_transit_gateway_route.tgw2_fw_default | tgw-rtb-064e2f1575529422b | 0.0.0.0/0 | tgw-attach-08c236efde613922b |
| aws_ec2_transit_gateway_route.tgw2_fw_vpc_b | tgw-rtb-064e2f1575529422b | 10.1.0.0/16 | tgw-attach-08c236efde613922b |
| aws_ec2_transit_gateway_route.tgw2_fw_vpc_c | tgw-rtb-064e2f1575529422b | 10.2.0.0/16 | tgw-attach-0989e560b674e039c |
| aws_ec2_transit_gateway_route.tgw2_fw_vpc_d | tgw-rtb-064e2f1575529422b | 10.3.0.0/16 | tgw-attach-002e2a419574cdc3c |

### New NACL Rules (must be imported or added)
| NACL ID | Rule | Egress | Protocol | Port | CIDR |
|---|---|---|---|---|---|
| acl-0695ef7e0e0b31db2 (nacl-b-trust) | 92 | false | tcp | 80 | 10.0.0.0/16 |
| acl-0695ef7e0e0b31db2 (nacl-b-trust) | 101 | true | tcp | 80 | 10.2.0.0/16 |
| acl-045e906a514372224 (nacl-c-dmz) | 99 | false | tcp | 80 | 10.1.2.0/24 |
| acl-045e906a514372224 (nacl-c-dmz) | 100 | false | tcp | 443 | 10.1.2.0/24 |
| acl-0c461e7c980d08c00 (nacl-c-portal) | 93 | false | tcp | 80 | 10.1.2.0/24 |
| acl-0c461e7c980d08c00 (nacl-c-portal) | 94 | false | tcp | 443 | 10.1.2.0/24 |
| acl-0c461e7c980d08c00 (nacl-c-portal) | 89 | true | tcp | 1024-65535 | 10.1.2.0/24 |

### New Security Group Rules (must be imported or added)
| SG ID | Name | Direction | Protocol | Port | CIDR |
|---|---|---|---|---|---|
| sg-0c044168b47ec90bf | lab-sg-c1-portal | ingress | tcp | 443 | 10.1.2.0/24 |
| sg-0e4f9a79d7ec3a0a6 | lab-sg-c2-gateway | ingress | tcp | 443 | 10.1.2.0/24 |
| sg-0637a7a019012e690 | lab-sg-c3-controller | ingress | tcp | 443 | 10.1.2.0/24 |

---

## EXECUTION STEPS

### Step 1 — Read and assess
Read the three files listed above. Identify which Terraform resources already
exist in the module and which are missing. Report your findings before writing
any code.

### Step 2 — Write terraform import blocks
For every resource listed above, write an import block using the correct
import ID format for each resource type:
- aws_ec2_transit_gateway_route_table: <route-table-id>
- aws_ec2_transit_gateway_route_table_association: <route-table-id>_<attachment-id>
- aws_ec2_transit_gateway_route: <route-table-id>_<cidr>
- aws_network_acl_rule: <nacl-id>:<rule-number>:<protocol>:<from-port>:<to-port>:<egress>
- aws_security_group_rule: use security_group_rule_id from the spike report

### Step 3 — Write resource blocks
Write the corresponding resource blocks for every import. Use the actual IDs
from this prompt as reference values to validate the plan output.

Key resource attributes to include:
- aws_ec2_transit_gateway_route_table: transit_gateway_id, tags (Name, Role, Project)
- aws_ec2_transit_gateway_vpc_attachment: add appliance_mode_support = "enable" to
  existing vpc-b attachment resources
- aws_ec2_transit_gateway_route_table_association: transit_gateway_attachment_id,
  transit_gateway_route_table_id
- aws_ec2_transit_gateway_route: destination_cidr_block, transit_gateway_attachment_id,
  transit_gateway_route_table_id
- aws_network_acl_rule: network_acl_id, rule_number, egress, protocol, cidr_block,
  from_port, to_port, rule_action
- aws_security_group_rule: security_group_id, type, protocol, from_port, to_port,
  cidr_blocks, description

### Step 4 — Run terraform plan
```powershell
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan -no-color 2>&1 | Tee-Object -FilePath artifacts\results\model23-tfplan-YYYYMMDD.txt
```

### Step 5 — Review the plan
Hard stops — if ANY of these appear in the plan, STOP immediately:
- destroy or replace of aws_vpc
- destroy or replace of aws_ec2_transit_gateway
- destroy or replace of aws_ec2_transit_gateway_vpc_attachment
- any resource not in the expected change list above

Expected plan profile:
- 4 new aws_ec2_transit_gateway_route_table (or 0 if imported)
- 6 new aws_ec2_transit_gateway_route_table_association (or 0 if imported)
- 9 new aws_ec2_transit_gateway_route (or 0 if imported)
- 2 ~ aws_ec2_transit_gateway_vpc_attachment (appliance_mode_support change only)
- 7 new aws_network_acl_rule (or 0 if imported)
- 3 new aws_security_group_rule (or 0 if imported)
- 0 destroys of any VPC, TGW, or attachment resource

### Step 6 — Format and validate
```powershell
terraform fmt -recursive
terraform validate
```

### Step 7 — Write plan review report
Write to: artifacts\results\model23-tfplan-review-YYYYMMDD.md

Include:
- Summary of all changes in the plan
- Confirmation that no hard-stop resources appear
- Any unexpected changes and explanation
- Final verdict: READY FOR OPERATOR APPLY or STOP

---

## RULES

- Do not run terraform apply
- Do not modify any existing VPC, TGW, or attachment resource blocks
- Do not remove any existing resources from the module
- If the plan shows unexpected destroys, diagnose before proceeding
- Use the actual resource IDs from this prompt — do not substitute or guess
- The old route tables (tgw1-rt-mgmt, tgw2-rt-customer) still exist in AWS
  and may still be in Terraform state — do not delete them, just leave them
