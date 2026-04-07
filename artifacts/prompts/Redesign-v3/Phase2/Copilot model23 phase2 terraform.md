# Phase 2 — Terraform Codification: Combined Model 2+3
# Date: YYYY-MM-DD (update when running)
# Prerequisite: Phase 1 CLI spike must be complete and all
#               connectivity tests must be passing before
#               running this prompt.

## MANDATORY FIRST STEPS

Read these files completely before taking any action:
  C:\Users\Willi\projects\Labs\artifacts\skills\terraform-skill.md
  C:\Users\Willi\projects\Labs\artifacts\skills\aws-cli-skill.md
  C:\Users\Willi\projects\Labs\artifacts\copilot-instructions-v1.md
  C:\Users\Willi\projects\Labs\artifacts\results\model23-cli-spike-YYYY-MM-DD.md

The CLI spike report is the source of truth. Every resource
created in Phase 1 must be represented in Terraform.

---

## EXECUTION RULES

- Do NOT run terraform apply until operator approves
- Do NOT destroy any existing resources
- Run terraform fmt on every file you modify
- Run terraform validate before reporting plan
- Write all new resources to the correct module files
- Follow the resource order from the spike report's
  "Terraform Resource Order" section

---

## STEP 1 — Read Current Terraform Code

Read these files completely:
  C:\Users\Willi\projects\Labs\terraform-aws\modules\network\main.tf
  C:\Users\Willi\projects\Labs\terraform-aws\environments\dev\main.tf
  C:\Users\Willi\projects\Labs\terraform-aws\environments\dev\variables.tf

Identify:
  - Where TGW route tables are currently defined
  - Where TGW attachments are defined
  - The for_each key patterns used
  - Where aws_route resources are defined

---

## STEP 2 — Import Existing Resources into State

The resources created during the CLI spike exist in AWS but
not in Terraform state. Import them before writing new code
to avoid duplicates on next apply.

```bash
cd C:\Users\Willi\projects\Labs\terraform-aws\environments\dev

# Import TGW1 Spoke RT (get ID from spike report)
terraform --% import 'module.network.aws_ec2_transit_gateway_route_table.spoke["tgw1"]' <TGW1_SPOKE_RT_ID>

# Import TGW2 Spoke RT
terraform --% import 'module.network.aws_ec2_transit_gateway_route_table.spoke["tgw2"]' <TGW2_SPOKE_RT_ID>

# Import updated route table associations
# (VPC-A, VPC-C moved to Spoke RT on TGW1)
# (VPC-D moved to Spoke RT on TGW2)
# Import format depends on current resource naming in module
```

Note: Import paths must match the exact Terraform resource
addresses used in the module. Read the module first to get
the correct addresses before running imports.

If import fails for any resource, do NOT proceed — document
the failure and try a different import path.

---

## STEP 3 — Write New Terraform Resources

Add these resources to the network module. Match the existing
for_each patterns exactly.

### New TGW route tables (Spoke RTs)

```hcl
# In modules/network/main.tf — add to TGW route table section

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  for_each           = aws_ec2_transit_gateway.this
  transit_gateway_id = each.value.id

  tags = merge(var.common_tags, {
    Name = "lab-rt-${each.key}-spoke"
    Role = "spoke"
  })
}
```

### Spoke RT associations (replacing old associations)

```hcl
# VPC-A and VPC-C associate to TGW1 Spoke RT
# VPC-D associates to TGW2 Spoke RT
# VPC-B remains on Firewall RT (existing, no change)

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = {
    "tgw1_a" = { rt = "tgw1", attachment = "tgw1_a" }
    "tgw1_c" = { rt = "tgw1", attachment = "tgw1_c" }
    "tgw2_d" = { rt = "tgw2", attachment = "tgw2_d" }
  }

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.value.rt].id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment].id
}
```

### Appliance mode on VPC-B attachments

```hcl
# In the existing TGW attachment resources for VPC-B, add:
# appliance_mode_support = "enable"

# Find the existing aws_ec2_transit_gateway_vpc_attachment
# resources for tgw1_b and tgw2_b and add this attribute
```

### Spoke RT routes (default → VPC-B)

```hcl
resource "aws_ec2_transit_gateway_route" "spoke_default" {
  for_each = {
    "tgw1" = { rt = aws_ec2_transit_gateway_route_table.spoke["tgw1"].id, attach = "tgw1_b" }
    "tgw2" = { rt = aws_ec2_transit_gateway_route_table.spoke["tgw2"].id, attach = "tgw2_b" }
  }

  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = each.value.rt
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.attach].id
}
```

### Firewall RT routes

```hcl
# Replace or supplement existing TGW routes
# These go in the existing Firewall RT (old single RT)
# Adapt key names to match existing for_each pattern

locals {
  firewall_rt_routes = {
    # TGW1 Firewall RT
    "tgw1_to_a"       = { rt = "tgw1", cidr = "10.0.0.0/16", attach = "tgw1_a" }
    "tgw1_to_c"       = { rt = "tgw1", cidr = "10.2.0.0/16", attach = "tgw1_c" }
    "tgw1_default"    = { rt = "tgw1", cidr = "0.0.0.0/0",   attach = "tgw1_a" }
    # TGW2 Firewall RT
    "tgw2_to_d"       = { rt = "tgw2", cidr = "10.3.0.0/16", attach = "tgw2_d" }
    "tgw2_to_c"       = { rt = "tgw2", cidr = "10.2.0.0/16", attach = "tgw2_c" }
  }
}
```

---

## STEP 4 — Run terraform plan

```bash
cd C:\Users\Willi\projects\Labs\terraform-aws\environments\dev
terraform --% plan -out=tfplan-model23 -no-color 2>&1 | Tee-Object -FilePath artifacts\results\plan-model23-YYYY-MM-DD.txt
```

Review the plan carefully:
- Should show 0 destroys of existing VPCs, TGWs, or attachments
- Should show changes to route table associations
- Should show new Spoke RT resources if not yet imported
- Should show appliance_mode_support changes on VPC-B attachments

STOP and report if plan shows any unexpected destroys.

Save plan summary to the report file.

---

## STEP 5 — Validate

```bash
terraform --% validate
terraform fmt -recursive C:\Users\Willi\projects\Labs\terraform-aws\modules\
```

All validation must pass before reporting ready for apply.

---

## STEP 6 — Write Phase 2 Report

Save to: artifacts/results/model23-phase2-terraform-YYYY-MM-DD.md

Include:
  - Resources imported (with import commands used)
  - Files modified (with line ranges)
  - Plan summary (add/change/destroy counts)
  - Any import failures and workarounds
  - Whether operator approval is needed before apply

Mark as:
  READY FOR OPERATOR APPLY
or
  STOP — REQUIRES REVIEW