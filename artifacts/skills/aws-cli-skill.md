# Skill: AWS CLI - Lab Validation and Operations

## Purpose

This skill defines the current AWS CLI workflow for validating and troubleshooting the TGW segmentation lab after deployment.

Use it for:

- live environment verification
- route, NACL, SG, TGW, and SSM inspection
- confirming whether a manual fix already exists before changing code
- cost and cleanup inspection

## Global Rules

1. Always use `--region`.
2. Confirm identity first.
3. Prefer `--output json` in PowerShell and write complex output to files.
4. Use `--query` only when it clearly simplifies the result.
5. Verify whether a live fix already exists before re-running a manual command.

## Current Architecture Facts

Assume these are true unless the user explicitly says the architecture has changed:

- no internal validation load balancers
- direct private-IP validation from VPC-A
- one public customer-entry load balancer only
- no custom Route 53 resources in use
- `alb_dns_name` is the compatibility output name for the public customer-entry load balancer

Current direct validation targets:

- `10.1.3.10`
- `10.2.2.10`
- `10.2.3.10`
- `10.2.4.10`

`10.3.1.10` must remain unreachable from VPC-A.

## Preflight

Always start with:

```powershell
aws sts get-caller-identity --output json --region us-east-1
aws configure get region
```

## PowerShell Output Rules

For complex resources, use:

```powershell
aws ec2 describe-network-acls --output json > nacl.json
aws ec2 describe-route-tables --output json > routes.json
aws ec2 describe-security-group-rules --output json > sg.json
```

Avoid `--output table` when the result is going to be parsed or saved.

JMESPath boolean filters with backticks are fragile in PowerShell. If a boolean query becomes awkward, capture JSON and filter afterward.

## Instance Inventory

```powershell
aws ec2 describe-instances `
  --filters "Name=tag:Project,Values=tgw-segmentation-lab" "Name=instance-state-name,Values=running" `
  --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value,ID:InstanceId,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,State:State.Name}" `
  --output json `
  --region us-east-1
```

## TGW Validation

List TGWs:

```powershell
aws ec2 describe-transit-gateways `
  --filters "Name=tag:Name,Values=lab-tgw*" `
  --output json `
  --region us-east-1
```

List TGW route tables:

```powershell
aws ec2 describe-transit-gateway-route-tables `
  --filters "Name=tag:Name,Values=tgw*-rt-*" `
  --output json `
  --region us-east-1
```

Search routes:

```powershell
aws ec2 search-transit-gateway-routes `
  --transit-gateway-route-table-id <tgw-rtb-id> `
  --filters "Name=state,Values=active" `
  --output json `
  --region us-east-1
```

Expected management TGW routes:

- `10.0.0.0/16`
- `10.1.0.0/16`
- `10.2.0.0/16`
- default `0.0.0.0/0` toward VPC-A for centralized egress

Expected customer TGW routes:

- `10.1.0.0/16`
- `10.2.0.0/16`
- `10.3.0.0/16`
- default `0.0.0.0/0` toward VPC-B

Important nuance:

- The A2 diagnostic role may not always include `ec2:SearchTransitGatewayRoutes`.
- If `search-transit-gateway-routes` fails on A2, treat that first as an IAM limitation, not automatic proof of a broken TGW route.

## Model 2+3 Two-Table TGW Validation

Current state:

- Model 2+3 two-table TGW routing is active and Terraform-applied as of 2026-04-07.
- Each TGW has a Spoke RT (`Role=spoke`) and Firewall RT (`Role=firewall`) for inspected traffic.
- VPC-B TGW attachments must have `Options.ApplianceModeSupport = enable`.
- TGW transit traffic uses AWS-managed TGW attachment ENIs in `10.1.2.0/24`; B1 OS-level `tcpdump` is not a valid transit visibility test.

List Model 2+3 route tables:

```powershell
aws ec2 describe-transit-gateway-route-tables `
  --filters "Name=tag:Role,Values=spoke,firewall" `
  --query "TransitGatewayRouteTables[*].{Name:Tags[?Key=='Name']|[0].Value,Role:Tags[?Key=='Role']|[0].Value,Id:TransitGatewayRouteTableId,State:State}" `
  --output json `
  --region us-east-1
```

Verify associations for a route table:

```powershell
aws ec2 get-transit-gateway-route-table-associations `
  --transit-gateway-route-table-id <RT_ID> `
  --query "Associations[*].{Attachment:TransitGatewayAttachmentId,Resource:ResourceId,Type:ResourceType,State:State}" `
  --output json `
  --region us-east-1
```

Search active routes in a specific route table:

```powershell
aws ec2 search-transit-gateway-routes `
  --transit-gateway-route-table-id <RT_ID> `
  --filters "Name=state,Values=active" `
  --query "Routes[*].{Cidr:DestinationCidrBlock,Type:Type,State:State,Attachments:TransitGatewayAttachments[*].ResourceId}" `
  --output json `
  --region us-east-1
```

Verify appliance mode on VPC-B attachments:

```powershell
aws ec2 describe-transit-gateway-vpc-attachments `
  --filters "Name=tag:Name,Values=*attach-vpc-b*" `
  --query "TransitGatewayVpcAttachments[*].{Name:Tags[?Key=='Name']|[0].Value,Id:TransitGatewayAttachmentId,Appliance:Options.ApplianceModeSupport,State:State}" `
  --output json `
  --region us-east-1
```

Expected pattern:

- TGW1 spoke RT: VPC-A and VPC-C associated, default route to VPC-B attachment.
- TGW1 firewall RT: VPC-B associated, routes back to VPC-A and VPC-C, default route to VPC-A for NAT egress.
- TGW2 spoke RT: VPC-C and VPC-D associated, default route to VPC-B attachment.
- TGW2 firewall RT: VPC-B associated, routes back to VPC-B, VPC-C, and VPC-D, default route to VPC-B.

IAM permissions useful for A2 diagnostics:

- `ec2:SearchTransitGatewayRoutes`
- `ec2:DescribeTransitGatewayRouteTables`
- `ec2:GetTransitGatewayRouteTableAssociations`
- `ec2:GetTransitGatewayRouteTablePropagations`
- `ec2:DescribeTransitGatewayVpcAttachments`

## Route Table Validation

Check the subnet route tables that matter, not just the VPC:

```powershell
aws ec2 describe-route-tables `
  --filters "Name=tag:Name,Values=lab-rt-*" `
  --output json `
  --region us-east-1
```

Critical current expectations:

- `lab-rt-b-untrust`
  - `10.0.0.0/16 -> TGW1`
  - `10.2.0.0/16 -> TGW1`
  - `10.3.0.0/16 -> TGW2`
  - `0.0.0.0/0 -> IGW`
- VPC-C route tables
  - `0.0.0.0/0 -> TGW1`
- VPC-A
  - `10.1.0.0/16 -> TGW1`
  - `10.2.0.0/16 -> TGW1`
  - no direct route to `10.3.0.0/16`

## NACL Validation

Inspect a specific NACL by tag:

```powershell
aws ec2 describe-network-acls `
  --filters "Name=tag:Name,Values=nacl-a" `
  --output json `
  --region us-east-1
```

Critical current rules:

- `nacl-a`
  - ingress `111` tcp `80` from `10.0.0.0/16`
  - ingress `112` tcp `443` from `10.0.0.0/16`
  - ingress `113` tcp `8443` from `10.0.0.0/16`
  - egress `125` tcp `80` to `10.2.0.0/16`
- `nacl-c-dmz`
  - egress `96` tcp `80` to `10.2.2.0/24`
- `nacl-c-portal`
  - VPC-A direct-access rules on `80`, `443`, and `22`

Always confirm both directions and the ephemeral return ranges.

## Security Group Validation

Inspect an SG:

```powershell
aws ec2 describe-security-group-rules `
  --filters "Name=group-id,Values=<sg-id>" `
  --output json `
  --region us-east-1
```

Current operator expectations:

- `B1` mgmt should allow `22` and `443` from `10.0.0.0/16`
- `C1` should allow `22`, `80`, and `443` from `10.0.0.0/16`
- `C2` should allow `22` and `443` from `10.0.0.0/16`
- `C3` should allow `22` and `443` from `10.0.0.0/16`

## Customer-Entry Load Balancer

There is still one public load balancer for the customer-entry path.

Check it with:

```powershell
aws elbv2 describe-load-balancers --output json --region us-east-1
aws elbv2 describe-target-groups --output json --region us-east-1
aws elbv2 describe-target-health --target-group-arn <tg-arn> --output json --region us-east-1
```

Use it only for the public customer-entry flow. Do not use old internal load balancer assumptions when troubleshooting B or C operator access.

## Route 53

Current state:

- no hosted zones
- no health checks
- no registered domains
- no reusable delegation sets
- no traffic policies
- no custom Route 53 Resolver endpoints

Do not assume DNS is part of the lab design unless the user explicitly adds it.

## SSM

Current expected diagnostic roles and profiles:

- `lab-a1-diagnostic-role`
- `lab-a1-diagnostic-profile`
- `lab-a2-diagnostic-role`
- `lab-a2-diagnostic-profile`

Current expected policies for the deploy-created diagnostic roles:

- `AmazonSSMManagedInstanceCore`
- `AmazonEC2ReadOnlyAccess`
- `ElasticLoadBalancingReadOnly`
- `AmazonS3ReadOnlyAccess`

Canonical SSM documents:

- `lab-netcheck-a1`
- `lab-netcheck-a2`

Canonical script payloads in S3:

- `s3://terraform-lab-wgl/ssm/netcheck/a1/netcheck-a1.ps1`
- `s3://terraform-lab-wgl/ssm/netcheck/a2/netcheck.sh`

Run the SSM documents before falling back to long manual SSH sessions when the task is routine validation.

## Windows Password Retrieval

```powershell
aws ec2 get-password-data `
  --instance-id <a1-instance-id> `
  --priv-launch-key tgw-lab-key.pem `
  --query "PasswordData" `
  --output text `
  --region us-east-1
```

## Cost And Cleanup

Use instance, NAT, TGW, EIP, ELB, and flow-log inspection to find billable resources. When the task is cleanup, prefer the repo teardown script over ad hoc delete commands:

```powershell
.\artifacts\scripts\teardown.ps1 -Environment dev -Force
```

## Useful Filters

| Goal | Filter |
| --- | --- |
| All lab instances | `Name=tag:Project,Values=tgw-segmentation-lab` |
| Running instances | `Name=instance-state-name,Values=running` |
| TGW attachments | `Name=state,Values=available` |
| Active TGW routes | `Name=state,Values=active` |
| Route table by tag | `Name=tag:Name,Values=lab-rt-*` |
| NACL by tag | `Name=tag:Name,Values=nacl-*` |
