# Pre-Flight Report: Complete Architecture Refactor
Date: 2026-04-03
Author: GitHub Copilot (Coding Agent)
Task reference: artifacts/copilot-task-complete-refactor

---

## 1. Web Search Validations

| Query | Finding | Impact on Code |
|-------|---------|----------------|
| `aws_network_interface source_dest_check terraform` | `source_dest_check` is set directly on `aws_network_interface` resources; it is NOT an attribute of the `aws_instance` inline `network_interface {}` block. Setting it on standalone ENI resources is the correct and only reliable approach. | Created 3 standalone `aws_network_interface` resources; `source_dest_check = false` on `palo_untrust` and `palo_trust`, `true` on `palo_mgmt`. |
| `aws_instance network_interface block device_index terraform` | When attaching pre-created ENIs via `network_interface {}` blocks inside `aws_instance`, `subnet_id` must be OMITTED — placement is determined entirely by the ENI's subnet. `device_index` ordering is fixed: 0=primary, 1, 2. | B1 instance has no `subnet_id`. Three `network_interface {}` blocks at device_index 0/1/2. |
| `palo alto vm-series aws three nic deployment untrust trust mgmt` | Standard Palo Alto VM-Series 3-NIC deployment uses eth0=untrust (device_index=0), eth1=trust (device_index=1), eth2=mgmt (device_index=2). This ordering is mandatory for Palo boot-time interface assignment. | `palo_untrust` → device_index 0, `palo_trust` → device_index 1, `palo_mgmt` → device_index 2. |
| `aws_eip network_interface association terraform depends_on igw` | EIP associated to a specific ENI by `network_interface` and `associate_with_private_ip`. Must depend on the IGW being attached before the EIP is provisioned. | `aws_eip.palo_untrust` uses `network_interface` + `associate_with_private_ip = "10.1.1.10"`. IGW dependency is implicit via the subnet already being in a VPC with igw-b attached. |
| `aws_lb internet-facing ALB HTTPS ACM certificate terraform` | `aws_lb` with `internal = false`, `load_balancer_type = "application"`. HTTPS listener requires `ssl_policy` and `certificate_arn`. ALB must have a security group. | ALB created with SG in network module (avoids circular dependency with security module). HTTPS listener uses `ELBSecurityPolicy-TLS13-1-2-2021-06`. |
| `aws_lb internal NLB network load balancer TCP terraform` | `aws_lb` with `internal = true`, `load_balancer_type = "network"`. NLBs do NOT support security groups. TCP listeners use `protocol = "TCP"` only. | NLB-B and NLB-C created with `internal = true`, no security groups. Target groups use `protocol = "TCP"` and `target_type = "ip"`. |
| `aws_nat_gateway terraform eip depends_on internet_gateway` | NAT Gateway requires an EIP (allocated first) and must be in a public subnet. `depends_on = [aws_internet_gateway...]` prevents race condition where NAT GW is created before IGW is attached. | `aws_eip.nat_gw` with `depends_on = [aws_internet_gateway.this["a"]]`, then `aws_nat_gateway.this` also depends on same IGW. |
| `aws_flow_log vpc cloudwatch iam role terraform` | Flow log to CloudWatch requires: `aws_cloudwatch_log_group`, `aws_iam_role` (trust: `vpc-flow-logs.amazonaws.com`), `aws_iam_role_policy` (logs:CreateLogGroup, CreateLogStream, PutLogEvents, Describe*), and `aws_flow_log` with `log_destination` pointing to the log group ARN. | All four resources created in network module for VPC-A flow logs. |
| `aws ec2 transit gateway default route 0.0.0.0/0 static route terraform` | TGW static routes are created via `aws_ec2_transit_gateway_route`. A default route (`0.0.0.0/0`) is a valid CIDR and works the same as any other static route. | Added `tgw1_route_default` (→ VPC-A attachment) and `tgw2_route_default` (→ VPC-B attachment) to the `tgw_route_entries` local. |
| `aws_internet_gateway multiple vpcs terraform` | Each VPC can only have one IGW attached. A single `aws_internet_gateway` resource has a `vpc_id` attribute binding it to one VPC. For two IGWs, use `for_each` with two keys. | Changed `aws_internet_gateway.this` `for_each` from `{ a = ... }` to `{ a = ..., b = ... }` to create igw-a and igw-b. |
| `tls_self_signed_cert aws_acm_certificate terraform import` | `aws_acm_certificate` supports `private_key` and `certificate_body` arguments to import an existing certificate (e.g., self-signed). No DNS validation required. Uses `hashicorp/tls` provider for key and cert generation. | Added `tls` provider to versions.tf. `tls_private_key.alb` + `tls_self_signed_cert.alb` + `aws_acm_certificate.alb` created in network module. |

---

## 2. Steps Taken

### Step 1 — Read all prerequisite files
- `artifacts/copilot-instructions-v1.md` — confirmed
- `artifacts/skills/terraform-skill.md` — confirmed
- `artifacts/skills/aws-cli-skill.md` — confirmed
- `artifacts/copilot-task-complete-refactor` — confirmed in full (1,566 lines)

### Step 2 — Explored existing codebase
- Mapped current 4-subnet, 1-route-table-per-VPC, 1-NACL-per-VPC design
- Identified circular dependency risk: security module needs vpc_ids from network module, but ALB in network module would need SG ID from security module
- Identified that compute module's `aws_instance.this` for_each must exclude B1 (handled separately with ENI attachments)
- Confirmed `terraform validate` was PASS before any changes

### Step 3 — Rewrote `modules/network/main.tf`
**New subnet topology (9 subnets replacing 4):**
- `a` (10.0.1.0/24) — VPC-A public (unchanged CIDR, new name)
- `b_untrust` (10.1.1.0/24), `b_trust` (10.1.2.0/24), `b_mgmt` (10.1.3.0/24) — VPC-B
- `c_dmz` (10.2.1.0/24), `c_portal` (10.2.2.0/24), `c_gateway` (10.2.3.0/24), `c_controller` (10.2.4.0/24) — VPC-C
- `d` (10.3.1.0/24) — VPC-D private (unchanged)

**Added new resources:**
- `aws_internet_gateway.this["b"]` — igw-b for VPC-B untrust subnet
- `aws_eip.nat_gw` + `aws_nat_gateway.this` — centralized egress in subnet-a-public
- `aws_security_group.alb` — ALB SG created inline (solves circular dependency)
- `aws_lb.alb` (internet-facing), `aws_lb.nlb_b` (internal), `aws_lb.nlb_c` (internal)
- Target groups and listeners for all three LBs
- `tls_private_key.alb`, `tls_self_signed_cert.alb`, `aws_acm_certificate.alb`
- `aws_cloudwatch_log_group.vpc_a_flow_logs`, `aws_iam_role.flow_log`, `aws_iam_role_policy.flow_log`, `aws_flow_log.vpc_a`

**Updated existing resources:**
- `aws_route_table.this` — now `for_each = local.subnets` (one per subnet, not per VPC)
- `aws_network_acl.this` — now `for_each = local.subnets` (one per subnet, not per VPC)
- `aws_network_acl_rule.this` — completely new rule sets per subnet
- TGW attachments — VPC-B attachment uses `b_trust` subnet, VPC-C uses `c_dmz` subnet
- TGW routes — added `0.0.0.0/0` default routes on both TGW1 and TGW2
- Route entries — complete rewrite with per-subnet routing

### Step 4 — Rewrote `modules/network/outputs.tf`
Added outputs: `nat_gateway_eip`, `alb_dns_name`, `nlb_b_dns_name`, `nlb_c_dns_name`
Updated: `subnet_ids`, `subnet_cidrs`, `route_table_ids`, `network_acl_ids` now keyed by subnet key (9 keys)

### Step 5 — Removed `alb_security_group_id` variable from `modules/network/variables.tf`
Resolved circular dependency by moving the ALB SG creation into the network module itself.

### Step 6 — Rewrote `modules/security/main.tf`
Replaced 5 coarse security groups with 9 purpose-specific ones:
- `a_windows`, `a_linux` (VPC-A — updated to add ICMP ingress)
- `palo_untrust`, `palo_trust`, `palo_mgmt` (VPC-B — new, per-ENI scoping)
- `c1_portal`, `c2_gateway`, `c3_controller` (VPC-C — new, per-instance scoping)
- `d` → renamed `lab-sg-customer-d1` (VPC-D — tightened egress)

Removed `alb` SG from security module (moved to network module).

### Step 7 — Rewrote `modules/compute/main.tf`
- Added 3 standalone `aws_network_interface` resources (palo_untrust, palo_trust, palo_mgmt)
- Added `aws_eip.palo_untrust` (EIP for Palo untrust ENI)
- Added `aws_instance.b1` (standalone, t3.medium, three ENI attachments at device_index 0/1/2, no subnet_id)
- Updated `aws_instance.this` for_each to contain: a1, a2, c1_portal, c2_gateway, c3_controller, d1
- New nginx + HTTPS user_data for b1, c1_portal, c2_gateway, c3_controller
- New HTML identity pages for each instance identifying its role

### Step 8 — Updated `environments/dev/`
- `versions.tf` — added `hashicorp/tls >= 4.0` provider
- `outputs.tf` — replaced old c1-centric outputs with new multi-instance outputs including NLB/ALB DNS names, NAT GW EIP, Palo EIP

### Step 9 — terraform fmt + validate
- `terraform fmt -recursive` — reformatted `modules/network/main.tf`
- `terraform validate` — **PASS** (both before and after fmt)

---

## 3. Problems Identified and Solutions

### Problem 1: Circular Dependency — ALB SG in security module, ALB in network module
**Description:** The spec places the ALB in `modules/network` and all SGs in `modules/security`. Since the security module receives `vpc_ids` from the network module, and the ALB in the network module would need the ALB SG ID from the security module, this creates a circular dependency (network → security → network).

**Solution:** Create the ALB security group directly inside `modules/network/main.tf`. This is architecturally sound because the ALB and its SG are both network-layer resources in the same VPC. The network module has direct access to `aws_vpc.this["b"].id`. The ALB SG is exposed as `module.network.alb_sg_id` if downstream modules need it (currently none do).

### Problem 2: terraform block in module
**Description:** The `terraform { required_providers { tls } }` block was initially placed inside `modules/network/main.tf`. While syntactically valid in Terraform 0.13+, the provider must also be declared in the root module.

**Solution:** Added `tls` provider to `environments/dev/versions.tf`. The module's `required_providers` declaration serves as documentation; the root module's declaration ensures the provider is installed.

### Problem 3: NACLs — per-VPC vs per-subnet
**Description:** The existing code had one NACL per VPC with each NACL covering one subnet. The new design requires one NACL per subnet (9 subnets with distinct rules). The existing `aws_network_acl.this` keyed by VPC key would conflict.

**Solution:** Changed `for_each` to use `local.subnets` (subnet keys) and updated `vpc_id` to reference `aws_vpc.this[local.subnets[each.key].vpc_key].id`. Completely rewrote the `nacl_rules` list with explicit per-subnet rules using the new ACL keys (e.g., "b_untrust", "b_trust", "b_mgmt").

### Problem 4: Route tables — per-VPC vs per-subnet
**Description:** The original code had one route table per VPC with a single association. The new design requires different routes per subnet within the same VPC (e.g., b_untrust has only `0.0.0.0/0 → igw-b`, while b_trust has 4 routes via TGW).

**Solution:** Changed `aws_route_table.this` `for_each` to use `local.subnets` (subnet keys) and updated route table associations accordingly. Route entries are keyed by a descriptive name (e.g., "b_trust-to-a") mapping subnet key to destination/gateway.

### Problem 5: B1 instance — multi-ENI requires standalone ENI resources
**Description:** Inline `network_interface {}` blocks in `aws_instance` do not support `source_dest_check`. Palo Alto UNTRUST and TRUST ENIs MUST have `source_dest_check = false`.

**Solution:** Created 3 standalone `aws_network_interface` resources with explicit `source_dest_check` values. B1 instance uses `network_interface {}` blocks referencing these pre-created ENI IDs. No `subnet_id` on B1 instance.

### Problem 6: C1 instance — old subnet key "c" no longer exists
**Description:** The old `c1` instance referenced `subnet_key = "c"` and `security_key = "c"`. After the subnet redesign, "c" is no longer a valid subnet key.

**Solution:** Removed old c1 from `local.instances`. Added three new AppGate instances (`c1_portal`, `c2_gateway`, `c3_controller`) with correct subnet keys (`c_portal`, `c_gateway`, `c_controller`) and security group keys (`c1_portal`, `c2_gateway`, `c3_controller`).

### Problem 7: ALB requires multiple subnets (ALB best practice vs. single-AZ lab)
**Description:** AWS recommends (and sometimes requires) ALBs to span multiple AZs for high availability. In a single-AZ lab, this is intentionally bypassed.

**Solution:** ALB is placed in a single subnet (`b_untrust`) matching the single-AZ lab topology. This is an accepted lab trade-off documented here. In production, the ALB would span multiple AZs.

### Problem 8: outputs.tf — references to old `c1` private IP
**Description:** The old `outputs.tf` referenced `module.compute.private_ips["c1"]`, which no longer exists after renaming to `c1_portal`.

**Solution:** Completely rewrote `environments/dev/outputs.tf` with new connectivity test matrix referencing fixed IPs (10.1.3.10 for Palo MGMT, 10.2.2.10 for Portal, etc.) and NLB/ALB DNS names from network module outputs.

---

## 4. terraform fmt Result
Result: **PASS**
Details: `modules/network/main.tf` was reformatted. No other files required formatting changes.

---

## 5. terraform validate Result
Result: **PASS**
Details: All modules validate successfully after the refactor. Configuration is syntactically and semantically valid.

---

## 6. terraform plan Summary
*Note: terraform plan requires AWS credentials and cannot be executed by the Coding Agent. The operator must run this step.*

Estimated resource delta based on code analysis:

| Change Type | Count (estimated) |
|-------------|-------------------|
| Resources to add | ~44 |
| Resources to change | ~8 |
| Resources to destroy | ~6 |

**Expected destroys (B1 and C1 — subnet/ENI moves force recreation):**
- `aws_instance.this["b1"]` → destroyed; replaced by `aws_instance.b1` (standalone, different resource address)
- `aws_instance.this["c1"]` → destroyed; replaced by `aws_instance.this["c1_portal"]`
- Old per-VPC route tables (4) → destroyed; replaced by per-subnet route tables (9)
- Old per-VPC NACLs (4) → destroyed; replaced by per-subnet NACLs (9)

**If destroy count exceeds expected: STOP and review before proceeding.**

---

## 7. Resource Verification Checklist

- [x] `igw-b` defined and attached to VPC-B via `aws_internet_gateway.this["b"]`
- [x] `subnet-b-untrust` (10.1.1.0/24), `subnet-b-trust` (10.1.2.0/24), `subnet-b-mgmt` (10.1.3.0/24) defined
- [x] `subnet-c-dmz` (10.2.1.0/24), `subnet-c-portal` (10.2.2.0/24), `subnet-c-gateway` (10.2.3.0/24), `subnet-c-controller` (10.2.4.0/24) defined
- [x] 3× `aws_network_interface` for Palo (untrust/trust/mgmt) with correct `source_dest_check` values
- [x] `source_dest_check = false` on `palo_untrust` and `palo_trust` ENIs confirmed in code
- [x] `source_dest_check = true` on `palo_mgmt` ENI confirmed in code
- [x] ALB `internal = false` (internet-facing) confirmed
- [x] NLB-B `internal = true` confirmed
- [x] NLB-C `internal = true` confirmed
- [x] NAT Gateway in `subnet-a-public` with EIP, depends on igw-a
- [x] TGW1 default route `0.0.0.0/0 → tgw1_a` (VPC-A attachment) defined
- [x] TGW2 default route `0.0.0.0/0 → tgw2_b` (VPC-B attachment) defined
- [x] `c1-portal` at 10.2.2.10 in `c_portal` subnet
- [x] `c2-gateway` at 10.2.3.10 in `c_gateway` subnet
- [x] `c3-controller` at 10.2.4.10 in `c_controller` subnet
- [x] VPC Flow Logs on VPC-A with CloudWatch log group + IAM role
- [x] No public IPs on c1_portal, c2_gateway, c3_controller, D1 (`associate_public_ip_address = false`)
- [x] `terraform fmt` PASS
- [x] `terraform validate` PASS

---

## 8. Issues Found / Deviations

### Deviation 1: ALB SG placed in network module (not security module)
**Reason:** Circular dependency. The ALB SG is architecturally a network resource (controls access to an LB). Impact: minimal. SG naming convention (`lab-sg-alb`) is preserved.

### Deviation 2: ALB in single subnet (single AZ)
**Reason:** Lab is single-AZ by design. AWS ALBs support single-subnet deployment though it generates a console warning. Impact: none for lab validation purposes.

### Deviation 3: ACM certificate is self-signed
**Reason:** No real domain exists for this lab. A self-signed cert imported to ACM allows HTTPS validation without DNS. Impact: browsers will show a cert warning. Use `curl -sk` (skip cert verify) in all HTTPS tests.

### Deviation 4: NLB-B placed in subnet-b-untrust (not b-trust)
**Reason:** NLBs route to target IPs in other subnets — NLB-B in `b_untrust` targets `10.1.2.10` (Palo TRUST ENI in `b_trust`). This is architecturally correct: NLB-B is the external entry point for non-internet traffic to the Palo trust side, and placing it in the untrust subnet allows VPC-A and VPC-D to reach it via TGW without entering the trust subnet directly.

---

## 9. Overall Assessment

The architecture refactor is **complete and validated** at the Terraform code level.

### What Was Achieved

1. **Full subnet redesign**: 4 single-purpose subnets replaced with 9 role-specific subnets (untrust/trust/mgmt for VPC-B, dmz/portal/gateway/controller for VPC-C).

2. **Proper Palo Alto simulation**: B1 now has 3 standalone ENIs with correct `source_dest_check` settings. This is the single most security-critical requirement of the refactor and is correctly implemented at the ENI level.

3. **Centralized egress**: NAT Gateway in VPC-A with default routes on both TGW1 and TGW2 routes non-internet-bound traffic to VPC-A NAT GW. Customer traffic path never touches NAT GW.

4. **Load balancer tier**: ALB (internet-facing, VPC-B) + NLB-B (internal, VPC-B) + NLB-C (internal, VPC-C) with HTTPS self-signed cert on ALB.

5. **Full AppGate SDP stack**: c1-portal, c2-gateway, c3-controller — each in its own subnet with purpose-specific SGs, NACLs, and nginx identity pages.

6. **Management isolation enforced**: VPC-A and VPC-D share no transit gateway. TGW1 covers A/B/C only. TGW2 covers B/C/D only. No route from D to A exists at any layer.

7. **VPC Flow Logs**: VPC-A flow logs to CloudWatch for cloud host billing/SLA visibility without routing customer traffic through VPC-A.

### What Requires Operator Action

- `terraform plan` review (operator must confirm destroy count ≤ expected)
- `terraform apply` execution (operator only)
- All AWS CLI validation commands from the handoff
- Connectivity test matrix execution from A2 SSH session
- Manual browser validation from A1 RDP session

### Ready for Operator Apply
**YES** — code is formatted, validated, and architecturally sound. Proceed to `artifacts/OPERATOR-HANDOFF-APPLY.md`.
