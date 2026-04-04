# Codex Prompt — Terraform Connectivity Fixes

## Context

This is a TGW segmentation lab with 4 VPCs, 2 Transit Gateways, per-subnet route tables, and per-subnet NACLs. All network resources are defined in `modules/network/main.tf`. Security groups are in `modules/security/main.tf`.

A set of connectivity fixes were validated live in the AWS console using EC2 Reachability Analyzer. Those fixes must now be codified into Terraform so they survive the next `terraform apply`. Do not change anything that is not listed here.

---

## Required Access Model (post-fix)

These paths must all be allowed:

| Source | Destination | Protocol |
|---|---|---|
| A1 (10.0.1.10) | B1 mgmt (10.1.3.10) | HTTPS 443 |
| A1 (10.0.1.10) | C1 portal (10.2.2.10) | HTTPS 443 |
| A2 (10.0.1.20) | B1 mgmt (10.1.3.10) | SSH 22 |
| A2 (10.0.1.20) | C1 portal (10.2.2.10) | SSH 22 |
| C1 (10.2.2.10) | B1 mgmt (10.1.3.10) | HTTPS 443, SSH 22 |
| C1 (10.2.2.10) | D1 (10.3.1.10) | HTTPS 443 |
| D1 (10.3.1.10) | C1 (10.2.2.10) | HTTPS 443 |

---

## File: `modules/network/main.tf`

### Change 1 — Add `10.3.0.0/16 → TGW2` to all VPC-C route tables

In the `route_entries` local, add 4 new entries. TGW2 key is `"tgw2"`.

```hcl
"c_portal-to-d"     = { subnet = "c_portal",     destination = "10.3.0.0/16", igw = null, tgw = "tgw2" }
"c_gateway-to-d"    = { subnet = "c_gateway",     destination = "10.3.0.0/16", igw = null, tgw = "tgw2" }
"c_controller-to-d" = { subnet = "c_controller",  destination = "10.3.0.0/16", igw = null, tgw = "tgw2" }
"c_dmz-to-d"        = { subnet = "c_dmz",         destination = "10.3.0.0/16", igw = null, tgw = "tgw2" }
```

### Change 2 — NACL rules

All NACL rules live in the `nacl_rules` list in `modules/network/main.tf`. Add the following entries. Do not remove any existing rules. Use the next available rule number in each block — check existing rules first to avoid conflicts.

#### `nacl-c-dmz` — add these rules:

```hcl
# Ingress
{ acl = "c_dmz", egress = false, rule_number = 113, protocol = "tcp", cidr_block = "10.2.0.0/16",  from_port = 1024, to_port = 65535 },
{ acl = "c_dmz", egress = false, rule_number = 114, protocol = "tcp", cidr_block = "10.3.0.0/16",  from_port = 1024, to_port = 65535 },
{ acl = "c_dmz", egress = false, rule_number = 115, protocol = "tcp", cidr_block = "10.2.2.0/24",  from_port = 22,   to_port = 22    },
{ acl = "c_dmz", egress = false, rule_number = 116, protocol = "tcp", cidr_block = "10.2.2.0/24",  from_port = 443,  to_port = 443   },
{ acl = "c_dmz", egress = false, rule_number = 123, protocol = "tcp", cidr_block = "10.1.3.0/24",  from_port = 1024, to_port = 65535 },
# Egress
{ acl = "c_dmz", egress = true,  rule_number = 105, protocol = "tcp", cidr_block = "10.1.3.0/24",  from_port = 22,   to_port = 22    },
{ acl = "c_dmz", egress = true,  rule_number = 106, protocol = "tcp", cidr_block = "10.1.3.0/24",  from_port = 443,  to_port = 443   },
{ acl = "c_dmz", egress = true,  rule_number = 107, protocol = "tcp", cidr_block = "10.3.0.0/16",  from_port = 443,  to_port = 443   },
{ acl = "c_dmz", egress = true,  rule_number = 121, protocol = "tcp", cidr_block = "10.2.2.0/24",  from_port = 1024, to_port = 65535 },
```

#### `nacl-c-portal` — add these rules:

```hcl
# Ingress
{ acl = "c_portal", egress = false, rule_number = 85, protocol = "tcp", cidr_block = "10.3.0.0/16", from_port = 443,  to_port = 443   },
# Egress
{ acl = "c_portal", egress = true,  rule_number = 85, protocol = "tcp", cidr_block = "10.3.0.0/16", from_port = 1024, to_port = 65535 },
{ acl = "c_portal", egress = true,  rule_number = 86, protocol = "tcp", cidr_block = "10.1.3.0/24", from_port = 22,   to_port = 22    },
{ acl = "c_portal", egress = true,  rule_number = 87, protocol = "tcp", cidr_block = "10.1.3.0/24", from_port = 443,  to_port = 443   },
{ acl = "c_portal", egress = true,  rule_number = 88, protocol = "tcp", cidr_block = "10.3.0.0/16", from_port = 443,  to_port = 443   },
```

#### `nacl-d` — add this rule:

```hcl
# Ingress
{ acl = "d", egress = false, rule_number = 115, protocol = "tcp", cidr_block = "10.2.0.0/16", from_port = 443, to_port = 443 },
```

#### `nacl-b-mgmt` — add these rules:

```hcl
# Ingress
{ acl = "b_mgmt", egress = false, rule_number = 90, protocol = "tcp", cidr_block = "10.2.0.0/16", from_port = 22,   to_port = 22    },
{ acl = "b_mgmt", egress = false, rule_number = 91, protocol = "tcp", cidr_block = "10.2.0.0/16", from_port = 443,  to_port = 443   },
# Egress
{ acl = "b_mgmt", egress = true,  rule_number = 90, protocol = "tcp", cidr_block = "10.2.0.0/16", from_port = 1024, to_port = 65535 },
```

#### `nacl-b-trust` — add these rules:

```hcl
# Ingress
{ acl = "b_trust", egress = false, rule_number = 85, protocol = "tcp", cidr_block = "10.2.0.0/16", from_port = 22,  to_port = 22  },
{ acl = "b_trust", egress = false, rule_number = 86, protocol = "tcp", cidr_block = "10.2.0.0/16", from_port = 443, to_port = 443 },
```

---

## File: `modules/security/main.tf`

### Change 3 — `aws_security_group.palo_mgmt`

Add to the `ingress` blocks:

```hcl
ingress {
  description = "SSH from VPC-C"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["10.2.0.0/16"]
}

ingress {
  description = "HTTPS from VPC-C"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["10.2.0.0/16"]
}
```

Add to the `egress` blocks:

```hcl
egress {
  description = "Ephemeral return to VPC-C"
  from_port   = 1024
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["10.2.0.0/16"]
}
```

### Change 4 — `aws_security_group.c1_portal`

Add to the `ingress` blocks:

```hcl
ingress {
  description = "HTTPS from VPC-D customer"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["10.3.0.0/16"]
}
```

Add to the `egress` blocks:

```hcl
egress {
  description = "SSH to B1 mgmt"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["10.1.3.0/24"]
}

egress {
  description = "HTTPS to B1 mgmt"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["10.1.3.0/24"]
}

egress {
  description = "Ephemeral return to VPC-D"
  from_port   = 1024
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["10.3.0.0/16"]
}
```

### Change 5 — `aws_security_group.d`

Add to the `ingress` blocks:

```hcl
ingress {
  description = "HTTPS from VPC-C AppGate"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["10.2.0.0/16"]
}
```

Add to the `egress` blocks:

```hcl
egress {
  description = "Ephemeral return to VPC-C"
  from_port   = 1024
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["10.2.0.0/16"]
}
```

---

## File: `modules/compute/main.tf`

### Change 6 — Disable source/dest check on C1 and D1 ENIs

Find the `aws_network_interface` resources for C1 (portal, `10.2.2.10`) and D1 (`10.3.1.10`) and set:

```hcl
source_dest_check = false
```

If C1 and D1 use `aws_instance` directly without a separate `aws_network_interface` resource, add to each instance:

```hcl
source_dest_check = false
```

---

## How to Apply

1. Make all changes above
2. Run from `environments/dev/`:
   ```powershell
   terraform --% plan -out=tfplan -no-color
   ```
3. Review the plan — expect:
   - `~` updates on `aws_network_acl_rule` resources (large churn is normal per the README)
   - `~` updates on `aws_route` resources for the 4 new VPC-C → VPC-D routes
   - `~` updates on `aws_security_group` resources for palo_mgmt, c1_portal, and d
   - `~` updates on ENI or instance source_dest_check
   - No destroys of VPCs, TGWs, or TGW attachments
4. Apply:
   ```powershell
   terraform --% apply tfplan
   ```

## Important Notes

- Do not consolidate or rewrite existing NACL rules — only add the new ones listed
- Do not change the `nacl_rule_map` key format — it is `"${acl}-${egress ? "egress" : "ingress"}-${rule_number}"`
- The `nacl-c-portal` already has rule numbers 90–130 in use — the new rules at 85–88 are intentionally below the existing block
- The `nacl-b-mgmt` already has rules 100–130 — the new rules at 90–91 are intentionally below
- The `nacl-b-trust` already has rules 90–130 — the new rules at 85–86 are intentionally below
- Large `aws_network_acl_rule` churn in the plan is expected and is not a stop condition
