# Skill: Terraform — AWS Infrastructure

## Purpose
This skill defines the patterns, validation rules, and best practices Copilot must follow
when reading, modifying, or applying Terraform configuration in this lab.

---

## Provider Version

This lab uses:
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}
```

Before running any apply, web-search: `hashicorp aws provider 5.x changelog breaking changes`
to confirm no arguments used in main.tf have been deprecated or renamed.

---

## Mandatory Pre-Apply Steps

Always run in this order. Never skip.

```bash
# 1. Format check
terraform fmt -check -recursive
# If it fails, run: terraform fmt -recursive

# 2. Syntax validation
terraform validate

# 3. Plan — review ALL changes before applying
terraform plan -out=tfplan

# 4. Review the plan output:
#    - "+" = new resource (expected on first apply)
#    - "~" = in-place update (review carefully)
#    - "-" = destroy (STOP and confirm with user before proceeding)
#    - "-/+" = destroy and recreate (STOP — this causes downtime)

# 5. Apply only after plan is reviewed
terraform apply tfplan
```

---

## Resource Naming Conventions

Every resource in this lab follows this pattern:

| Resource type | Name pattern | Example |
|---|---|---|
| VPC | `lab-vpc-<letter>-<role>` | `lab-vpc-a-cloudhost` |
| Subnet | `lab-subnet-<letter>` | `lab-subnet-b` |
| Security Group | `lab-sg-vpc-<letter>` | `lab-sg-vpc-b` |
| NACL | `nacl-vpc-<letter>` | `nacl-vpc-c` |
| Instance | `lab-<letter><number>-<role>` | `lab-b1-paloalto` |
| TGW | `lab-tgw<n>-<segment>` | `lab-tgw1-mgmt` |
| TGW RT | `tgw<n>-rt-<segment>` | `tgw1-rt-mgmt` |
| TGW Attachment | `tgw<n>-attach-vpc-<letter>` | `tgw2-attach-vpc-b` |

All resources must have a `Name` tag matching the name pattern above.

---

## CIDR Map — Memorize This

| VPC | CIDR | Role |
|-----|------|------|
| VPC-A | `10.0.0.0/16` | Cloud Host (Management) |
| VPC-B | `10.1.0.0/16` | Palo Alto NGFW sim |
| VPC-C | `10.2.0.0/16` | AppGate SDP sim |
| VPC-D | `10.3.0.0/16` | Customer |

Subnet CIDRs are the first /24 of each VPC (e.g., `10.0.1.0/24`, `10.1.1.0/24`).

---

## Security Group Rules — What Is and Is Not Allowed

### Allowed open to `0.0.0.0/0` ingress
- Port 22 (SSH) on `sg_a_linux` only — A2 is the SSH jump box
- Port 3389 (RDP) on `sg_a_windows` only — A1 is the Windows browser box

### Everything else must be scoped to internal CIDRs
Use the CIDR map above. Example pattern:
```hcl
ingress {
  description = "HTTP from VPC-A"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/16"]   # NOT 0.0.0.0/0
}
```

### Egress
- A1 and A2 egress `0.0.0.0/0` is acceptable (they need internet for Chrome/yum)
- B1, C1, D1 egress should be scoped to known internal CIDRs only

---

## NACL Rules — Key Concepts

NACLs are **stateless**. This means:
- Every allowed flow needs an inbound AND an outbound rule
- Return traffic uses **ephemeral ports**: `1024-65535`
- If a NACL is missing ephemeral port rules, TCP connections will fail silently even if the Security Group is correct

### Pattern for any TCP service (e.g., HTTP to B1 from A2)

On B1's NACL (nacl-vpc-b):
```
INBOUND:  allow TCP from 10.0.0.0/16 port 80      ← the request
OUTBOUND: allow TCP to   10.0.0.0/16 ports 1024-65535  ← the response
```

On A's NACL (nacl-vpc-a):
```
OUTBOUND: allow TCP to   10.1.0.0/16 port 80       ← the request
INBOUND:  allow TCP from 10.1.0.0/16 ports 1024-65535  ← the response
```

### Protocol codes in Terraform NACLs
```hcl
protocol = "tcp"   # TCP
protocol = "udp"   # UDP
protocol = "icmp"  # ICMP — use from_port = -1, to_port = -1
protocol = "-1"    # All protocols — use from_port = 0, to_port = 0
```

---

## AMI Data Sources — Always Use Filters, Never Hardcode IDs

```hcl
# Amazon Linux 2023
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Windows Server 2022
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
```

Web-search before using: `aws ami filter al2023 amazon linux 2023 latest`
to confirm the filter string is still correct for the target region.

---

## Transit Gateway — Critical Settings

These must always be present on every TGW resource:
```hcl
default_route_table_association = "disable"
default_route_table_propagation = "disable"
```

If these are missing, VPCs will auto-associate with a default route table,
which breaks the segmentation design entirely.

Every TGW attachment must also explicitly disable defaults:
```hcl
transit_gateway_default_route_table_association = false
transit_gateway_default_route_table_propagation = false
```

---

## Common Errors and Fixes

| Error | Cause | Fix |
|---|---|---|
| `InvalidTransitGatewayID.NotFound` | TGW not yet ready | Add `depends_on` or wait — TGW takes 2-3 min |
| `DependencyViolation` on destroy | Attachments must be deleted before TGW | Terraform handles ordering if resources are in same config |
| NACL rule conflict | Two rules with same rule number | Each rule number must be unique per NACL per direction |
| Windows password not available | Too soon after boot | Wait 4-5 minutes, then run `get-password-data` |
| nginx not serving on B1/C1 | user_data didn't run | Check `/var/log/cloud-init-output.log` on the instance |

---

## Outputs Reference

After apply, run:
```bash
terraform output                      # all outputs
terraform output private_ips          # B1, C1, D1 private IPs
terraform output a1_windows_public_ip # Windows RDP target
terraform output a2_linux_public_ip   # Linux SSH target
terraform output test_commands        # full test matrix with real IPs
terraform output rdp_password_decrypt_command  # CLI to decrypt Windows password
```

## 2026-04-03 - Architecture refactor destroy count expectations

- A full per-VPC to per-subnet NACL refactor can legitimately destroy about 100 `aws_network_acl_rule` resources in one plan. Treat that as expected churn when old per-VPC ACLs are being replaced by per-subnet ACLs.
- Set the operator safety threshold from resource-type analysis, not a raw destroy count. Large NACL-rule churn can be safe, but any destroy or replace involving `aws_vpc`, `aws_ec2_transit_gateway`, or `aws_ec2_transit_gateway_vpc_attachment` still requires an immediate stop and explicit review.
