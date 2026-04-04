# Network Troubleshooting Toolbox
# Skill: network-troubleshooting
# Version: 2.0 - 2026-04-04

## Scope

Use this skill for the current simplified TGW segmentation lab.
The lab no longer depends on internal `NLB-B` or `NLB-C` for operator
validation. VPC-A reaches the private targets directly by IP.

Write findings to:
`artifacts/results/YYYY-MM-DD_network-diagnosis-<issue>.md`

## Current Architecture

```text
Internet
  |
  +-- ALB customer entry in VPC-B
  |
  +-- A1 Windows (10.0.1.10) in VPC-A
  |     RDP browser host
  |
  +-- A2 Linux (10.0.1.20) in VPC-A
        SSH jump host

TGW1
  |
  +-- VPC-A 10.0.0.0/16
  +-- VPC-B 10.1.0.0/16
  |     B1 Palo mgmt target: 10.1.3.10
  +-- VPC-C 10.2.0.0/16
        C1 portal:     10.2.2.10
        C2 gateway:    10.2.3.10
        C3 controller: 10.2.4.10

TGW2
  |
  +-- VPC-B 10.1.0.0/16
  +-- VPC-C 10.2.0.0/16
  +-- VPC-D 10.3.0.0/16
        D1 customer: 10.3.1.10
```

## Expected Healthy State

- `A1` can browse to:
  - `https://10.1.3.10`
  - `https://10.2.2.10`
  - `https://10.2.3.10`
  - `https://10.2.4.10`
- `A2` can SSH and curl those same private targets directly
- `A2` cannot reach `D1` at `10.3.1.10`
- The shared NAT gateway egress IP is used by private instances
- No internal `NLB-B` or `NLB-C` load balancers remain

## First Step

Run the canonical validation script from `A2`:

```bash
KEY_PATH=~/tgw-lab-key.pem bash ~/netcheck.sh
```

Canonical repo copy:
`artifacts/scripts/netcheck.sh`

If the script output is enough to identify the problem, stop there and
document the finding. Do not keep digging without a reason.

## Decision Tree

```text
Can A2 reach B1/C1/C2/C3 directly?
|
+-- NO
|   +-- Check VPC-A route table to 10.1.0.0/16 and 10.2.0.0/16
|   +-- Check NACLs on subnet-a and the destination subnet
|   +-- Check destination security group
|   +-- Run Reachability Analyzer ENI-to-ENI
|   +-- If path is open, SSH to the instance and check nginx / listeners
|
+-- YES, but A1 browser still fails
|   +-- Treat as A1 browser or certificate issue first
|   +-- Check Windows routing, proxy, and the self-signed cert warning
|
+-- A2 can reach D1
|   +-- This is an isolation breach
|   +-- Check VPC-A and VPC-D route tables immediately
|
+-- Private instance internet egress fails
    +-- Check NAT gateway state and VPC-A default route
    +-- Verify the instance is private and not using A2's public path
```

## Tool Reference

### Tool 1: Direct Validation Matrix

Use the scripted check first, or run the core commands manually from `A2`:

```bash
curl -sk -o /dev/null -w "%{http_code}\n" https://10.1.3.10
curl -s  -o /dev/null -w "%{http_code}\n" http://10.2.2.10
curl -sk -o /dev/null -w "%{http_code}\n" https://10.2.2.10
curl -sk -o /dev/null -w "%{http_code}\n" https://10.2.3.10
curl -sk -o /dev/null -w "%{http_code}\n" https://10.2.4.10
curl -s  --connect-timeout 5 -o /dev/null -w "%{http_code}\n" http://10.3.1.10
```

Expected:
- `200` for B1/C1/C2/C3
- `000` for `D1`

### Tool 2: Route Checks

Verify VPC-A has the TGW routes required for VPC-B and VPC-C:

```bash
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<VPC_A_ID>" \
  --query 'RouteTables[*].Routes[*].{Dest:DestinationCidrBlock,TGW:TransitGatewayId,GW:GatewayId,State:State}' \
  --output table --region us-east-1
```

Expected:
- `10.1.0.0/16 -> TGW1`
- `10.2.0.0/16 -> TGW1`
- no `10.3.0.0/16` route from VPC-A

### Tool 3: NACL Checks

Critical current rules:

- `nacl-a`
  - ingress `111` tcp `80` from `10.0.0.0/16`
  - ingress `112` tcp `443` from `10.0.0.0/16`
  - ingress `113` tcp `8443` from `10.0.0.0/16`
  - egress `125` tcp `80` to `10.2.0.0/16`
- `nacl-c-dmz`
  - egress `96` tcp `80` to `10.2.2.0/24`

Inspect a subnet NACL with:

```bash
aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=<SUBNET_ID>" \
  --query 'NetworkAcls[0].Entries[*].{Rule:RuleNumber,Dir:Egress,Proto:Protocol,Action:RuleAction,CIDR:CidrBlock,From:PortRange.From,To:PortRange.To}' \
  --output table --region us-east-1
```

### Tool 4: Security Group Checks

Inspect a destination SG:

```bash
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=<SG_ID>" \
  --query 'SecurityGroupRules[?IsEgress==`false`].{Port:FromPort,ToPort:ToPort,Protocol:IpProtocol,CIDR:CidrIpv4,Desc:Description}' \
  --output table --region us-east-1
```

Expected inbound examples:

- `B1` mgmt:
  - `22` from `10.0.0.0/16`
  - `443` from `10.0.0.0/16`
- `C1`:
  - `22`, `80`, `443`, `8443` from `10.0.0.0/16`

### Tool 5: Reachability Analyzer

Use direct ENI-to-ENI checks now. Do not model traffic through internal
NLBs because those load balancers are gone.

Example:

```bash
aws ec2 create-network-insights-path \
  --source <A2_ENI_ID> \
  --destination <C1_ENI_ID> \
  --protocol TCP \
  --destination-port 443 \
  --region us-east-1
```

If the path is blocked, inspect:
- `SUBNET_ACL_RESTRICTION`
- `SECURITY_GROUP_RULE_RESTRICTION`
- `ROUTE_NOT_FOUND`

Always clean up the analysis resources after reading the result.

### Tool 6: Instance-Side Checks

If network controls look correct, SSH from `A2` and validate the service:

```bash
ssh -i tgw-lab-key.pem ec2-user@10.2.2.10
systemctl is-active nginx
ss -tln | grep -E ':80 |:443 '
curl -sk https://localhost -o /dev/null -w "%{http_code}\n"
curl -s http://localhost -o /dev/null -w "%{http_code}\n"
```

### Tool 7: A1 Browser Validation

If `A2` succeeds but `A1` does not:

- treat the network as probably healthy
- check Chrome certificate handling
- on the warning page, type `thisisunsafe`
- verify A1 can route to `10.1.0.0/16` and `10.2.0.0/16`

## Known Lessons

### 2026-04-04 - Direct private-IP model

- Internal `NLB-B` and `NLB-C` were removed to simplify the lab.
- Use direct private IPs for operator validation from VPC-A.
- `B1` should be validated on the mgmt interface `10.1.3.10`, not on the
  old trust or untrust service IPs.
- `C3` is validated on `443`, not `8443`.

### 2026-04-04 - A2 IAM limitation

- The A2 diagnostic role does not have `ec2:SearchTransitGatewayRoutes`.
- If that AWS CLI command fails on A2, treat it as an IAM limitation first.
- Use route-table inspection and direct path validation as the primary proof.

## Rules

- Default to read-only commands during diagnosis
- Do not run `terraform apply` or `terraform destroy`
- Do not change SGs, NACLs, or route tables unless the operator explicitly
  asks for a remediation session instead of a diagnosis session
