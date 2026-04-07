# Network Troubleshooting Toolbox
# Skill: network-troubleshooting
# Version: 3.0 - 2026-04-04

## Scope

Use this skill for the current direct-access TGW segmentation lab.

The lab no longer uses separate internal validation load balancers for operator validation. Operator checks from VPC-A go directly to private IPs.

Write findings to:
`artifacts/results/YYYY-MM-DD_network-diagnosis-<issue>.md`

## Current Architecture

```text
Internet
  |
  +-- A1 Windows (10.0.1.10) in VPC-A
  |     RDP browser host
  |
  +-- A2 Linux (10.0.1.20) in VPC-A
  |     SSH jump host and bootstrap host
  |
  +-- customer-entry load balancer in VPC-B untrust

TGW1
  |
  +-- VPC-A 10.0.0.0/16
  +-- VPC-B 10.1.0.0/16
  |     B1 Palo mgmt: 10.1.3.10
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
  - `http://10.2.2.10`
  - `https://10.2.2.10`
  - `https://10.2.3.10`
  - `https://10.2.4.10`
- `A2` can SSH and curl those same private targets
- `A2` cannot reach `D1`
- the public customer-entry load balancer remains separate from the operator path
- no internal load balancers remain
- no custom Route 53 resources are involved
- Model 2+3 two-table TGW routing is active: spoke traffic is forced through VPC-B inspection route tables
- VPC-B TGW attachments have appliance mode enabled
- destination NACLs and SGs account for TGW attachment subnet source traffic from `10.1.2.0/24`

## First Step

Prefer the existing netcheck automation before doing manual SSH work.

Best options:

1. Run the SSM document `lab-netcheck-a2`
2. Or run the canonical A2 script:

```bash
KEY_PATH=~/tgw-lab-key.pem bash ~/netcheck.sh
```

Canonical repo copy:
`artifacts/scripts/netcheck.sh`

If the script gives a clear answer, stop there and write the report. Do not continue exploring without a reason.

## Decision Tree

```text
Can A2 reach 10.1.3.10 / 10.2.2.10 / 10.2.3.10 / 10.2.4.10 directly?
|
+-- NO
|   +-- Check the exact subnet route table first
|   +-- For Model 2+3, check spoke/firewall TGW route table associations
|   +-- Check nacl-a, nacl-b-trust, nacl-c-dmz, and the destination subnet path
|   +-- Check destination security groups for `10.1.2.0/24` transit ingress
|   +-- Use Reachability Analyzer if the basic controls still look right
|   +-- If the path is open, inspect the instance service
|
+-- YES, but A1 browser still fails
|   +-- Treat it as an A1 browser, Windows, or certificate issue first
|   +-- Check Chrome warning handling
|   +-- Check Windows route state and proxy behavior
|
+-- A2 can reach D1
|   +-- This is an isolation breach
|   +-- Inspect VPC-A and VPC-D route tables immediately
|
+-- Linux node internet egress fails
    +-- Check VPC-C default routes to TGW1
    +-- Check VPC-A NAT state
    +-- Check whether the node is using the A2 bootstrap path correctly
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

- `200` for `B1`, `C1`, `C2`, and `C3`
- `000` for `D1`

### Tool 2: Route Checks

Check the actual subnet route tables, not only the VPC:

```bash
aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=lab-rt-*" \
  --output json \
  --region us-east-1
```

Critical expectations:

- `lab-rt-b-untrust` has return routes to VPC-A, VPC-C, and VPC-D
- VPC-C route tables have `0.0.0.0/0 -> TGW1`
- VPC-A has routes to VPC-B and VPC-C, but not to VPC-D
- Model 2+3 Spoke RTs have `0.0.0.0/0 -> VPC-B`
- Model 2+3 Firewall RTs are associated with VPC-B and route back to the spokes

Model 2+3 TGW route table checks:

```bash
aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Role,Values=spoke,firewall" \
  --output json \
  --region us-east-1

aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id <rt-id> \
  --output json \
  --region us-east-1

aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <rt-id> \
  --filters "Name=state,Values=active" \
  --output json \
  --region us-east-1
```

### Tool 3: NACL Checks

Critical current rules:

- `nacl-a`
  - ingress `111` tcp `80`
  - ingress `112` tcp `443`
  - ingress `113` tcp `8443`
  - egress `125` tcp `80`
- `nacl-c-dmz`
  - ingress `99` tcp `80` from `10.1.2.0/24`
  - ingress `100` tcp `443` from `10.1.2.0/24`
  - egress `96` tcp `80` to `10.2.2.0/24`
- `nacl-b-trust`
  - ingress `92` tcp `80` from `10.0.0.0/16`
  - egress `101` tcp `80` to `10.2.0.0/16`
- `nacl-c-portal`
  - ingress `93` tcp `80` from `10.1.2.0/24`
  - ingress `94` tcp `443` from `10.1.2.0/24`
  - egress `89` tcp `1024-65535` to `10.1.2.0/24`

Inspect with:

```bash
aws ec2 describe-network-acls \
  --filters "Name=tag:Name,Values=nacl-*" \
  --output json \
  --region us-east-1
```

### Tool 4: Security Group Checks

Inspect the destination SG:

```bash
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=<sg-id>" \
  --output json \
  --region us-east-1
```

Expected inbound examples:

- `B1` mgmt:
  - `22` from `10.0.0.0/16`
  - `443` from `10.0.0.0/16`
- `C1`:
  - `22`, `80`, `443` from `10.0.0.0/16`
- `C1`, `C2`, and `C3` after Model 2+3:
  - `443` from `10.1.2.0/24`

### Tool 5: Reachability Analyzer

Use direct ENI-to-ENI paths. Do not model old internal load balancers.

Example:

```bash
aws ec2 create-network-insights-path \
  --source <a2-eni-id> \
  --destination <c1-eni-id> \
  --protocol TCP \
  --destination-port 443 \
  --region us-east-1
```

Key failure reasons:

- `SUBNET_ACL_RESTRICTION`
- `SECURITY_GROUP_RULE_RESTRICTION`
- `ROUTE_NOT_FOUND`

### Tool 6: Instance-Side Checks

If the network path looks right, inspect the service:

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
- check Chrome certificate handling first
- on the warning page, type `thisisunsafe`
- verify A1 has the expected route state

### Tool 8: SSM Netchecks

Prefer these before long manual sessions:

- `lab-netcheck-a1`
- `lab-netcheck-a2`

The script payloads and output capture paths are already standardized in the repo and in S3.

### Tool 9: Two-Table TGW Pattern Verifier

Use this after Model 2+3 deployment or when a path looks asymmetric.

Checks:

- Spoke RTs exist for TGW1 and TGW2.
- Firewall RTs exist for TGW1 and TGW2.
- Spoke VPCs are associated with Spoke RTs.
- VPC-B is associated with Firewall RTs.
- Spoke RT default routes point to VPC-B attachments.
- Firewall RTs have routes back to the spoke VPC CIDRs.
- VPC-B TGW attachments have appliance mode enabled.
- Actual traffic stability: 10 consecutive `curl -sk https://10.2.2.10` requests from A2 return `200`.

Do not use `tcpdump` on B1 as proof of transit visibility. TGW uses AWS-managed attachment ENIs in `10.1.2.0/24`; B1 can show zero packets even when the inspected path is healthy.

## Known Lessons

### 2026-04-07 - Model 2+3 Terraform-applied steady state

- Model 2+3 route tables, routes, associations, NACL rules, and SG rules are now Terraform-managed.
- The post-apply Terraform plan returned no changes.
- Teardown should let Terraform remove managed TGW route tables/routes/associations. Do not manually delete those resources first unless state management changes.

### 2025-07-14 - Model 2+3 tcpdump and Reachability Analyzer limits

- B1 tcpdump is not a valid proof of TGW transit visibility because TGW traffic uses AWS-managed attachment ENIs.
- Reachability Analyzer can false-negative multi-hop TGW inspection paths because it does not model TGW source-IP substitution to the attachment subnet.
- Prefer actual curl results plus TGW route table, NACL, SG, and appliance-mode checks.

### 2026-04-04 - Direct private-IP model

- Legacy internal validation load balancers were removed.
- `B1` operator validation should use `10.1.3.10`, not the untrust or trust ENI.
- `C3` validation should use `443`, not `8443`, for the landing page.

### 2026-04-04 - A2 IAM limitation

- The A2 diagnostic role may not have `ec2:SearchTransitGatewayRoutes` in every context.
- If that call fails on A2, do not confuse it with a routing outage.

### 2026-04-04 - Route 53 is not part of the lab

- No custom hosted zones or Resolver endpoints are part of the current design.
- Do not add Route 53 assumptions to troubleshooting unless the operator explicitly changes the architecture.

## Rules

- default to read-only commands during diagnosis
- do not run `terraform apply` or `terraform destroy`
- do not change SGs, NACLs, route tables, or SSM docs unless the session is explicitly a remediation session
