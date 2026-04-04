# Operator Handoff — Complete Architecture Refactor
Date: 2026-04-03
Prepared by: GitHub Copilot (Coding Agent)
Status: Ready for operator apply

---

## What Was Built

The existing single-subnet-per-VPC lab was refactored into a production-representative
DoD-adjacent IL4/IL5 architecture. VPC-B now has three subnets (untrust/trust/mgmt)
for a three-ENI Palo Alto NGFW simulation. VPC-C now has four subnets housing separate
AppGate Portal, Gateway, and Controller simulations. An internet-facing ALB, two internal
NLBs, a centralized NAT Gateway, and VPC Flow Logs on VPC-A were added. All transit
gateway route tables have default routes for centralized egress.

---

## Pre-Apply Checklist (operator confirms before running apply)

- [ ] AWS credentials configured and pointing to correct account
- [ ] Correct region set: `us-east-1`
- [ ] `terraform-aws/environments/dev/backend.hcl` present and correct (S3 bucket + DynamoDB table exist)
- [ ] `tgw-lab-key.pem` available locally (matches the public key in `terraform.tfvars`)
- [ ] terraform plan has been reviewed (see `artifacts/results/2026-04-03_complete-architecture-refactor.md`)
- [ ] Destroy count in plan is within expected range (see Plan Notes below)
- [ ] No unexpected destroys of TGW attachments, VPCs, or TGW resources

### Plan Notes — Expected Destroys

These resources will be **destroyed and recreated** — this is expected:

| Resource | Reason |
|----------|--------|
| `aws_instance.this["b1"]` | Old B1 no longer exists; replaced by `aws_instance.b1` with 3 ENIs |
| `aws_instance.this["c1"]` | Old C1 no longer exists; replaced by `aws_instance.this["c1_portal"]` |
| `aws_route_table.this["a"]` through `["d"]` (4 resources) | Per-VPC route tables replaced by per-subnet route tables |
| `aws_route_table_association.this[...]` (4 resources) | Associated with old route tables |
| `aws_network_acl.this["a"]` through `["d"]` (4 resources) | Per-VPC NACLs replaced by per-subnet NACLs |
| All old `aws_network_acl_rule.this[...]` | Rule sets completely replaced |

**If plan shows destroys of: TGWs, TGW attachments, VPCs, or any resource not listed above — STOP and do not apply.**

---

## Apply Commands

```bash
cd terraform-aws/environments/dev
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
# Review plan output carefully — confirm expected destroys only
terraform apply tfplan
```

---

## Expected Apply Duration

| Resource | Estimated Time |
|----------|---------------|
| NAT Gateway provisioning | ~2 minutes |
| ALB/NLB provisioning | ~3 minutes |
| EC2 instance recreation (B1, C1→c1_portal) | ~3 minutes |
| New EC2 instances (c2-gateway, c3-controller) | ~2 minutes |
| TGW route updates + default routes | ~1 minute |
| ACM certificate import | ~30 seconds |
| VPC Flow Logs setup | ~30 seconds |
| **Total estimated** | **~12 minutes** |

---

## Post-Apply — Get Connection Details

```bash
terraform output
terraform output -json > artifacts/results/outputs-2026-04-03.json

# Key outputs to note:
terraform output a2_linux_public_ip       # SSH entry point
terraform output a1_windows_public_ip     # RDP entry point
terraform output palo_untrust_eip         # Palo Alto internet-facing EIP
terraform output nat_gateway_eip          # NAT GW EIP (verify egress tests return this IP)
terraform output alb_dns_name             # Internet-facing ALB DNS
terraform output nlb_b_dns_name           # NLB-B (Palo trust — internal)
terraform output nlb_c_dns_name           # NLB-C (AppGate portal — internal)
```

---

## Windows RDP (A1)

```powershell
# Decrypt password:
aws ec2 get-password-data \
  --instance-id <a1_instance_id_from_output> \
  --priv-launch-key tgw-lab-key.pem \
  --query 'PasswordData' --output text \
  --region us-east-1

# RDP to: ${A1_IP}:3389
# Username: Administrator
# Password: <decrypted above>
```

---

## Linux SSH (A2)

```bash
ssh -i tgw-lab-key.pem ec2-user@${A2_IP}
```

---

## AWS CLI Validation Commands

Run these **in order** after apply completes. Wait 2-3 minutes for all instances to reach running state.

### 1. Confirm all instances running

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=lab-*" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].{
      Name:Tags[?Key==`Name`]|[0].Value,
      ID:InstanceId,
      PrivateIP:PrivateIpAddress,
      PublicIP:PublicIpAddress,
      State:State.Name}' \
  --output table --region us-east-1
```

Expected instances and IPs:
| Name | Private IP | Public IP |
|------|-----------|-----------|
| lab-a1-windows | 10.0.1.10 | (public) |
| lab-a2-linux | 10.0.1.20 | (public) |
| lab-b1-paloalto (UNTRUST ENI) | 10.1.1.10 | palo_untrust_eip |
| lab-b1-paloalto (TRUST ENI)   | 10.1.2.10 | none — use as SSH hop to D1 |
| lab-b1-paloalto (MGMT ENI)    | 10.1.3.10 | none — SSH from A2 for mgmt |
| lab-c1-portal | 10.2.2.10 | none |
| lab-c2-gateway | 10.2.3.10 | none |
| lab-c3-controller | 10.2.4.10 | none |
| lab-d1-customer | 10.3.1.10 | none |

Note: SSH to B1 for management tests uses 10.1.3.10 (MGMT ENI).
SSH hop to D1 uses 10.1.2.10 (TRUST ENI) — the only ENI with a
TGW2 return path to VPC-D.

### 2. Confirm Palo Alto ENIs and source_dest_check

```bash
# Get B1 instance ID first
B1_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=lab-b1-paloalto" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text --region us-east-1)

aws ec2 describe-network-interfaces \
  --filters "Name=attachment.instance-id,Values=${B1_ID}" \
  --query 'NetworkInterfaces[*].{
      ENI:NetworkInterfaceId,
      PrivateIP:PrivateIpAddress,
      SourceDestCheck:SourceDestCheck,
      DeviceIndex:Attachment.DeviceIndex}' \
  --output table --region us-east-1
```

Expected:
| DeviceIndex | PrivateIP | SourceDestCheck |
|-------------|-----------|-----------------|
| 0 | 10.1.1.10 | **false** (UNTRUST) |
| 1 | 10.1.2.10 | **false** (TRUST) |
| 2 | 10.1.3.10 | **true** (MGMT) |

**If any of DeviceIndex 0 or 1 shows `true` for SourceDestCheck — this is a critical failure.**

### 3. Confirm load balancers

```bash
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[*].{
      Name:LoadBalancerName,
      Scheme:Scheme,
      Type:Type,
      State:State.Code,
      DNS:DNSName}' \
  --output table --region us-east-1
```

Expected:
| Name | Scheme | Type | State |
|------|--------|------|-------|
| lab-alb-customer-entry | internet-facing | application | active |
| lab-nlb-b-palo-trust | internal | network | active |
| lab-nlb-c-appgate-portal | internal | network | active |

### 4. Confirm target group health (wait 2-3 min after apply)

```bash
# Get all target group ARNs
aws elbv2 describe-target-groups \
  --query 'TargetGroups[?starts_with(TargetGroupName, `lab-`)].{
      Name:TargetGroupName,
      ARN:TargetGroupArn,
      Port:Port,
      Protocol:Protocol}' \
  --output table --region us-east-1

# Check health for each (repeat for each ARN):
aws elbv2 describe-target-health \
  --target-group-arn <TG_ARN> \
  --query 'TargetHealthDescriptions[*].{
      Target:Target.Id,
      Port:Target.Port,
      Health:TargetHealth.State,
      Reason:TargetHealth.Reason}' \
  --output table --region us-east-1
```

Expected targets:
| Target Group | Target IP | Port | Expected Health |
|-------------|-----------|------|-----------------|
| lab-alb-tg-palo-untrust | 10.1.1.10 | 443 | healthy (after nginx starts) |
| lab-nlb-b-palo-trust-80 | 10.1.2.10 | 80 | healthy |
| lab-nlb-b-palo-trust-443 | 10.1.2.10 | 443 | healthy |
| lab-nlb-c-appgate-portal-80 | 10.2.2.10 | 80 | healthy |
| lab-nlb-c-appgate-portal-443 | 10.2.2.10 | 443 | healthy |

### 5. Confirm NAT Gateway available

```bash
aws ec2 describe-nat-gateways \
  --filter Name=state,Values=available \
  --query 'NatGateways[*].{
      ID:NatGatewayId,
      SubnetId:SubnetId,
      EIP:NatGatewayAddresses[0].PublicIp,
      State:State}' \
  --output table --region us-east-1
```

### 6. Confirm TGW default routes

```bash
# Get TGW1 route table ID
TGW1_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw1-rt-mgmt" \
  --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
  --output text --region us-east-1)

aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id ${TGW1_RT} \
  --filters Name=state,Values=active \
  --query 'Routes[*].{CIDR:DestinationCidrBlock,Type:Type,State:State}' \
  --output table --region us-east-1
# Expected: 0.0.0.0/0 static route present

# Repeat for TGW2:
TGW2_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw2-rt-customer" \
  --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
  --output text --region us-east-1)

aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id ${TGW2_RT} \
  --filters Name=state,Values=active \
  --query 'Routes[*].{CIDR:DestinationCidrBlock,Type:Type,State:State}' \
  --output table --region us-east-1
# Expected: 0.0.0.0/0 static route present (→ VPC-B attachment)
```

### 7. Confirm TGW attachment subnets (critical — validates TGW fix)

```bash
aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=state,Values=available" \
  --query 'TransitGatewayVpcAttachments[*].{
      Name:Tags[?Key==`Name`]|[0].Value,
      VpcId:VpcId,
      Subnets:SubnetIds,
      State:State}' \
  --output table --region us-east-1
```

Expected subnet placement:

| Attachment | Must use subnet |
|------------|----------------|
| tgw1-attach-vpc-b | subnet-b-trust (10.1.2.x) — NOT b-untrust |
| tgw2-attach-vpc-b | subnet-b-trust (10.1.2.x) — NOT b-untrust |
| tgw1-attach-vpc-c | subnet-c-dmz (10.2.1.x) |
| tgw2-attach-vpc-c | subnet-c-dmz (10.2.1.x) |
| tgw1-attach-vpc-a | subnet-a (10.0.1.x) |
| tgw2-attach-vpc-d | subnet-d (10.3.1.x) |

If VPC-B attachment shows any subnet other than 10.1.2.x — STOP.
The TGW fix was not applied correctly. Do not proceed with
connectivity tests until this is resolved.

---

## Connectivity Test Matrix

**Run these once after terraform apply to populate all test variables:**
```bash
# Run these once after terraform apply to populate all test variables
export NLB_B_DNS=$(terraform output -raw nlb_b_dns_name)
export NLB_C_DNS=$(terraform output -raw nlb_c_dns_name)
export ALB_DNS=$(terraform output -raw alb_dns_name)
export NAT_EIP=$(terraform output -raw nat_gateway_eip)
export A2_IP=$(terraform output -raw a2_linux_public_ip)
export A1_IP=$(terraform output -raw a1_windows_public_ip)

echo "NLB_B_DNS : ${NLB_B_DNS}"
echo "NLB_C_DNS : ${NLB_C_DNS}"
echo "ALB_DNS   : ${ALB_DNS}"
echo "NAT_EIP   : ${NAT_EIP}"
```

**SSH to A2 first:**
```bash
ssh -i tgw-lab-key.pem ec2-user@${A2_IP}
```

### From operator laptop — ALB public internet test

Run this from your LOCAL machine (not from A2):

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)

# Full public internet → ALB → Palo path — MUST return 200
curl -sk -o /dev/null -w "%{http_code}" https://${ALB_DNS}
```

Expected: 200
This is the only test that validates the complete inbound customer path
end to end from the public internet through the ALB.

### From A2 — Management path tests

```bash
# Palo MGMT ENI — MUST WORK
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@10.1.3.10
curl -sk -o /dev/null -w "%{http_code}" https://10.1.3.10

# NLB-B (Palo trust) — MUST WORK (both 200)
curl -s  -o /dev/null -w "%{http_code}" http://${NLB_B_DNS}
curl -sk -o /dev/null -w "%{http_code}" https://${NLB_B_DNS}

# NLB-C (AppGate Portal) — MUST WORK (200)
curl -sk -o /dev/null -w "%{http_code}" https://${NLB_C_DNS}

# AppGate Controller admin UI — MUST WORK (200)
curl -sk -o /dev/null -w "%{http_code}" https://10.2.4.10:8443

# AppGate Gateway — MUST WORK (200)
curl -sk -o /dev/null -w "%{http_code}" https://10.2.3.10

# D1 direct — MUST FAIL (000 or timeout)
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://10.3.1.10
```

### From B1 MGMT ENI — Centralized egress test

```bash
# SSH: A2 → B1 MGMT ENI
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@10.1.3.10

# Centralized egress via TGW1 → VPC-A → NAT GW
curl -s --connect-timeout 10 https://checkip.amazonaws.com
# Expected: returns ${NAT_EIP}
```

### From c1-portal — AppGate collective test

```bash
# SSH: A2 → c1-portal
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@10.2.2.10

curl -sk -o /dev/null -w "%{http_code}" https://10.2.3.10        # Gateway — MUST WORK (200)
curl -sk -o /dev/null -w "%{http_code}" https://10.2.4.10:8443   # Controller — MUST WORK (200)
curl -s  --connect-timeout 10 https://checkip.amazonaws.com       # NAT GW EIP — MUST return ${NAT_EIP}
```

### From D1 — Customer path tests

```bash
# SSH: A2 → B1 TRUST ENI (10.1.2.10) → D1
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@10.1.2.10
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@10.3.1.10

# NLB-C (Portal via TGW2) — MUST WORK (200)
curl -sk -o /dev/null -w "%{http_code}" https://${NLB_C_DNS}

# NLB-B (Palo) — MUST WORK (200)
curl -s  -o /dev/null -w "%{http_code}" http://${NLB_B_DNS}

# Controller direct — MUST FAIL (000)
curl -sk --connect-timeout 5 -o /dev/null -w "%{http_code}" https://10.2.4.10:8443

# VPC-A direct — MUST FAIL (000 — no shared TGW)
curl -s  --connect-timeout 5 -o /dev/null -w "%{http_code}" http://10.0.1.10
```

### A1 Windows (manual — RDP in, open Chrome)

```
http://${NLB_B_DNS}       → Palo Alto NGFW page     MUST LOAD
https://${NLB_C_DNS}      → AppGate Portal page      MUST LOAD (cert warning OK)
https://10.2.4.10:8443        → Controller admin UI      MUST LOAD
http://10.3.1.10              → D1                       MUST FAIL
```

---

## Expected Results Summary

| Test | Expected | Pass/Fail |
|------|----------|-----------|
| A2 → Palo MGMT SSH (10.1.3.10) | PASS | |
| A2 → NLB-B HTTP | 200 | |
| A2 → NLB-B HTTPS | 200 | |
| A2 → NLB-C HTTPS | 200 | |
| A2 → Controller 8443 | 200 | |
| A2 → Gateway HTTPS | 200 | |
| A2 → D1 direct | FAIL/000 | |
| B1 MGMT → internet | `${NAT_EIP}` | |
| c1-portal → c2-gateway | 200 | |
| c1-portal → c3-controller | 200 | |
| c1-portal → internet | `${NAT_EIP}` | |
| D1 → NLB-C | 200 | |
| D1 → NLB-B | 200 | |
| D1 → Controller direct | FAIL/000 | |
| D1 → VPC-A direct | FAIL/000 | |
| Laptop → ALB HTTPS (public internet) | 200 | |
| A1 Chrome → NLB-B | LOADS | |
| A1 Chrome → NLB-C | LOADS | |
| A1 Chrome → Controller | LOADS | |
| ALB internet-facing | HTTPS 200 | |

---

## Record Results

After completing all tests, record pass/fail in:
```
artifacts/results/2026-04-03_post-apply-validation.md
```

Use the table above as the template.
