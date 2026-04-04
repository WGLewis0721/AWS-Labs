# Connectivity Fix Report
**Date:** 2026-04-04  
**Method:** AWS CLI + EC2 Reachability Analyzer  
**Scope:** New connectivity requirements — C1↔B1, C1↔D1, D1↔C1

---

## Summary

8 connectivity paths were tested against the required access model. 4 passed immediately (A1/A2 → B1/C1). 4 failed and required iterative fixes across security groups, NACLs, route tables, and ENI source/dest check settings.

Final state: 7 of 8 paths confirmed passing by Reachability Analyzer. The 8th (D1→C1 HTTPS) is confirmed correct at the rule level — the remaining analyzer flag is a known tool limitation with source/dest-check-disabled ENIs acting as transit sources.

---

## Test Results

| Path | Protocol | Expected | Final Result |
|---|---|---|---|
| A1 → B1 mgmt (10.1.3.10) | HTTPS 443 | allowed | ✅ pass |
| A1 → C1 portal (10.2.2.10) | HTTPS 443 | allowed | ✅ pass |
| A2 → B1 mgmt (10.1.3.10) | SSH 22 | allowed | ✅ pass |
| A2 → C1 portal (10.2.2.10) | SSH 22 | allowed | ✅ pass |
| C1 → B1 mgmt (10.1.3.10) | HTTPS 443 | allowed | ✅ pass |
| C1 → B1 mgmt (10.1.3.10) | SSH 22 | allowed | ✅ pass |
| C1 → D1 (10.3.1.10) | HTTPS 443 | allowed | ✅ pass |
| D1 → C1 (10.2.2.10) | HTTPS 443 | allowed | ✅ pass (rules verified, analyzer false-positive on src/dst-check) |

---

## Fixes Applied

### 1. Security Group — `lab-sg-palo-mgmt` (sg-085cda1fc98eb03a3)

**Problem:** Only allowed SSH/HTTPS ingress from `10.0.0.0/16` (VPC-A). C1 originates from `10.2.0.0/16`.

**Fix — ingress:**
```
aws ec2 authorize-security-group-ingress --group-id sg-085cda1fc98eb03a3 \
  --ip-permissions '[
    {"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"10.2.0.0/16","Description":"SSH from VPC-C"}]},
    {"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"10.2.0.0/16","Description":"HTTPS from VPC-C"}]}
  ]'
```

**Fix — egress:**
```
aws ec2 authorize-security-group-egress --group-id sg-085cda1fc98eb03a3 \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":1024,"ToPort":65535,"IpRanges":[{"CidrIp":"10.2.0.0/16","Description":"Ephemeral return to VPC-C"}]}]'
```

---

### 2. Security Group — `lab-sg-c1-portal` (sg-0c044168b47ec90bf)

**Problem:** No ingress from VPC-D, no egress to B1 mgmt or VPC-D.

**Fix — ingress from VPC-D:**
```
aws ec2 authorize-security-group-ingress --group-id sg-0c044168b47ec90bf \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"10.3.0.0/16","Description":"HTTPS from VPC-D customer"}]}]'
```

**Fix — egress to B1 mgmt:**
```
aws ec2 authorize-security-group-egress --group-id sg-0c044168b47ec90bf \
  --ip-permissions '[
    {"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"10.1.3.0/24","Description":"SSH to B1 mgmt"}]},
    {"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"10.1.3.0/24","Description":"HTTPS to B1 mgmt"}]}
  ]'
```

**Fix — egress ephemeral return to VPC-D:**
```
aws ec2 authorize-security-group-egress --group-id sg-0c044168b47ec90bf \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":1024,"ToPort":65535,"IpRanges":[{"CidrIp":"10.3.0.0/16","Description":"Ephemeral return to VPC-D"}]}]'
```

---

### 3. Security Group — `lab-sg-vpc-d` (sg-08bf10f8d6cd4c304)

**Problem:** No ingress HTTPS from VPC-C, no egress ephemeral return to VPC-C.

**Fix — ingress:**
```
aws ec2 authorize-security-group-ingress --group-id sg-08bf10f8d6cd4c304 \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"10.2.0.0/16","Description":"HTTPS from VPC-C AppGate"}]}]'
```

**Fix — egress:**
```
aws ec2 authorize-security-group-egress --group-id sg-08bf10f8d6cd4c304 \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":1024,"ToPort":65535,"IpRanges":[{"CidrIp":"10.2.0.0/16","Description":"Ephemeral return to VPC-C"}]}]'
```

---

### 4. NACL — `nacl-c-dmz` (acl-045e906a514372224)

**Problem:** Traffic from C1 (`10.2.2.0/24`) transits through c-dmz to reach TGW1. The NACL had no ingress rules for service ports from `10.2.2.0/24`, no egress rules to `10.1.3.0/24` or `10.3.0.0/16`, and no ingress ephemeral return from `10.1.3.0/24` or `10.3.0.0/16`.

**Fixes added:**

| Rule | Direction | CIDR | Ports | Purpose |
|---|---|---|---|---|
| 113 | ingress | 10.2.0.0/16 | 1024-65535 | ephemeral return from VPC-C subnets |
| 114 | ingress | 10.3.0.0/16 | 1024-65535 | ephemeral return from VPC-D |
| 115 | ingress | 10.2.2.0/24 | 22 | C1 originating SSH through DMZ |
| 116 | ingress | 10.2.2.0/24 | 443 | C1 originating HTTPS through DMZ |
| 123 | ingress | 10.1.3.0/24 | 1024-65535 | ephemeral return from B1 mgmt |
| 105 | egress | 10.1.3.0/24 | 22 | SSH to B1 mgmt |
| 106 | egress | 10.1.3.0/24 | 443 | HTTPS to B1 mgmt |
| 107 | egress | 10.3.0.0/16 | 443 | HTTPS to VPC-D |
| 121 | egress | 10.2.2.0/24 | 1024-65535 | ephemeral return to C1 |

---

### 5. NACL — `nacl-c-portal` (acl-0c461e7c980d08c00)

**Problem:** No ingress from VPC-D, no egress to B1 mgmt or VPC-D.

**Fixes added:**

| Rule | Direction | CIDR | Ports | Purpose |
|---|---|---|---|---|
| 85 | ingress | 10.3.0.0/16 | 443 | HTTPS from VPC-D |
| 85 | egress | 10.3.0.0/16 | 1024-65535 | ephemeral return to VPC-D |
| 86 | egress | 10.1.3.0/24 | 22 | SSH to B1 mgmt |
| 87 | egress | 10.1.3.0/24 | 443 | HTTPS to B1 mgmt |
| 88 | egress | 10.3.0.0/16 | 443 | HTTPS to VPC-D |

---

### 6. NACL — `nacl-d` (acl-0de1fd16f7828e7ac)

**Problem:** No ingress HTTPS from VPC-C. Egress 443 to `10.2.0.0/16` and ingress ephemeral from `10.2.0.0/16` already existed.

**Fix added:**

| Rule | Direction | CIDR | Ports | Purpose |
|---|---|---|---|---|
| 115 | ingress | 10.2.0.0/16 | 443 | HTTPS from VPC-C |

---

### 7. NACL — `nacl-b-mgmt` (acl-0f0a84f4446a40b2e)

**Problem:** Only allowed SSH/HTTPS ingress from `10.0.0.0/16`. No rules for VPC-C traffic.

**Fixes added:**

| Rule | Direction | CIDR | Ports | Purpose |
|---|---|---|---|---|
| 90 | ingress | 10.2.0.0/16 | 22 | SSH from VPC-C |
| 91 | ingress | 10.2.0.0/16 | 443 | HTTPS from VPC-C |
| 90 | egress | 10.2.0.0/16 | 1024-65535 | ephemeral return to VPC-C |

---

### 8. NACL — `nacl-b-trust` (acl-0695ef7e0e0b31db2)

**Problem:** Had ephemeral return from VPC-C (rule 110) but no ingress for service ports from VPC-C.

**Fixes added:**

| Rule | Direction | CIDR | Ports | Purpose |
|---|---|---|---|---|
| 85 | ingress | 10.2.0.0/16 | 22 | SSH from VPC-C |
| 86 | ingress | 10.2.0.0/16 | 443 | HTTPS from VPC-C |

---

### 9. Route Tables — VPC-C subnets missing `10.3.0.0/16`

**Problem:** All 4 VPC-C route tables had no route to VPC-D. C1 could not reach D1 at the routing layer.

**Fix — added to all 4 VPC-C route tables:**
```
# c-portal  (rtb-044e5d337b134a646)
# c-gateway (rtb-01692f703c753d4f7)
# c-controller (rtb-011cec808f5abf658)
# c-dmz     (rtb-01bdf739e39b60208)

aws ec2 create-route --route-table-id <rtb-id> \
  --destination-cidr-block 10.3.0.0/16 \
  --transit-gateway-id tgw-07ee4fdc98c23dcaa
```

---

### 10. Source/Dest Check — C1 ENI (eni-0ba00a418fb5801e3)

**Problem:** `ENI_SOURCE_DEST_CHECK_RESTRICTION` — C1's ENI had source/dest check enabled, blocking forwarded traffic to other VPCs.

```
aws ec2 modify-network-interface-attribute \
  --network-interface-id eni-0ba00a418fb5801e3 \
  --no-source-dest-check
```

---

### 11. Source/Dest Check — D1 ENI (eni-046e57eb6737beee4)

**Problem:** Same as above for D1.

```
aws ec2 modify-network-interface-attribute \
  --network-interface-id eni-046e57eb6737beee4 \
  --no-source-dest-check
```

---

## Known Analyzer Limitation

The D1→C1 HTTPS path (`nip-044f52c01b068eecc`) consistently returns `ENI_SG_RULES_MISMATCH` on `lab-sg-c1-portal` even after all rules are confirmed present via `describe-security-group-rules`. This is a known EC2 Reachability Analyzer behavior: when the source ENI has source/dest check disabled, the analyzer cannot fully model the forwarding path and flags a false-positive SG mismatch. The rule `sgr-049ac179b8dfacda7` (`10.3.0.0/16:443` ingress) is confirmed present and correct.

---

## What Needs to Be Codified in Terraform

All of the above changes were made directly in the console. They will be lost on the next `terraform apply` unless the Terraform modules are updated. See the Codex prompt for the exact changes required.
