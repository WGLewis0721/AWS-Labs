# Skill: AWS CLI — Lab Validation and Operations

## Purpose
This skill defines the AWS CLI patterns Copilot must use to validate, inspect, and
troubleshoot the TGW segmentation lab after deployment.

---

## Global Rules

1. Always include `--region <REGION>` on every command — never rely on environment defaults
2. Always confirm resource state after creation before moving to the next step
3. Use `--output table` for human-readable inspection, `--output json` when parsing output
4. Use `--query` to filter output to only what is needed
5. Web-search `aws cli <command> <resource>` before running any command you haven't used recently

---

## Pre-Flight: Confirm AWS Identity

Always run this first to confirm you're operating in the correct account and region:

```bash
aws sts get-caller-identity
aws configure get region
```

Expected: the account ID should match the account where Terraform was applied.

---

## Instance Inventory

Get all lab instances with their IPs and state:

```bash
aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=lab-*" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].{
      Name:Tags[?Key==`Name`]|[0].Value,
      ID:InstanceId,
      Type:InstanceType,
      PrivateIP:PrivateIpAddress,
      PublicIP:PublicIpAddress,
      State:State.Name,
      AZ:Placement.AvailabilityZone
    }' \
  --output table \
  --region <REGION>
```

---

## Transit Gateway Validation

### List TGWs
```bash
aws ec2 describe-transit-gateways \
  --filters "Name=tag:Name,Values=lab-tgw*" \
  --query 'TransitGateways[*].{Name:Tags[?Key==`Name`]|[0].Value,ID:TransitGatewayId,State:State}' \
  --output table \
  --region <REGION>
```

### List TGW Route Tables
```bash
aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw*-rt-*" \
  --query 'TransitGatewayRouteTables[*].{Name:Tags[?Key==`Name`]|[0].Value,ID:TransitGatewayRouteTableId,State:State}' \
  --output table \
  --region <REGION>
```

### Validate Routes in a TGW Route Table
```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <TGW_RT_ID> \
  --filters "Name=state,Values=active" \
  --query 'Routes[*].{CIDR:DestinationCidrBlock,State:State,Type:Type,Attachment:TransitGatewayAttachments[0].ResourceId}' \
  --output table \
  --region <REGION>
```

Expected routes for TGW-1 (MGMT RT):
- `10.0.0.0/16` → VPC-A attachment
- `10.1.0.0/16` → VPC-B attachment
- `10.2.0.0/16` → VPC-C attachment

Expected routes for TGW-2 (CUSTOMER RT):
- `10.3.0.0/16` → VPC-D attachment
- `10.1.0.0/16` → VPC-B attachment
- `10.2.0.0/16` → VPC-C attachment

### Validate TGW Attachments
```bash
aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=state,Values=available" \
  --query 'TransitGatewayVpcAttachments[*].{Name:Tags[?Key==`Name`]|[0].Value,ID:TransitGatewayAttachmentId,VPC:VpcId,State:State}' \
  --output table \
  --region <REGION>
```

---

## VPC Route Table Validation

### Describe route table for a specific VPC
```bash
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query 'RouteTables[*].Routes[*].{Dest:DestinationCidrBlock,Target:TransitGatewayId,GW:GatewayId,State:State}' \
  --output table \
  --region <REGION>
```

Expected for VPC-A route table:
- `0.0.0.0/0` → Internet Gateway (IGW)
- `10.1.0.0/16` → TGW-1
- `10.2.0.0/16` → TGW-1
- No entry for `10.3.0.0/16` (VPC-D must not be reachable from A)

Expected for VPC-D route table:
- `10.1.0.0/16` → TGW-2
- `10.2.0.0/16` → TGW-2
- No entry for `10.0.0.0/16` (VPC-A must not be reachable from D)
- No IGW entry (D1 is private)

---

## Security Group Validation

### Describe a Security Group's rules
```bash
aws ec2 describe-security-groups \
  --group-ids <SG_ID> \
  --query 'SecurityGroups[0].{
      Name:GroupName,
      Ingress:IpPermissions,
      Egress:IpPermissionsEgress
    }' \
  --output json \
  --region <REGION>
```

### Quick ingress-only view
```bash
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=<SG_ID>" \
  --query 'SecurityGroupRules[?IsEgress==`false`].{
      Port:FromPort,
      ToPort:ToPort,
      Protocol:IpProtocol,
      CIDR:CidrIpv4,
      Desc:Description
    }' \
  --output table \
  --region <REGION>
```

### Security check — find any SG with 0.0.0.0/0 ingress on non-management ports
```bash
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=sg-vpc-*" \
  --query "SecurityGroups[*].{
      Name:GroupName,
      OpenRules:IpPermissions[?contains(IpRanges[].CidrIp, '0.0.0.0/0')].{Port:FromPort,Proto:IpProtocol}
    }" \
  --output json \
  --region <REGION>
```

Flag any result that shows `0.0.0.0/0` on ports other than 22 and 3389.

---

## NACL Validation

### Describe NACL for a subnet
```bash
aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=<SUBNET_ID>" \
  --query 'NetworkAcls[0].Entries[*].{
      RuleNum:RuleNumber,
      Direction:Egress,
      Protocol:Protocol,
      Action:RuleAction,
      CIDR:CidrBlock,
      PortFrom:PortRange.From,
      PortTo:PortRange.To
    }' \
  --output table \
  --region <REGION>
```

Note: `Direction: false` = inbound, `Direction: true` = outbound.

### Verify ephemeral port rules exist
After getting NACL entries, confirm both inbound and outbound have rules covering `1024-65535`.
If missing, TCP sessions will appear to work at the SG layer but responses will be dropped.

---

## Windows Password Retrieval (A1)

```bash
# Wait ~4 minutes after instance launch, then:
aws ec2 get-password-data \
  --instance-id <A1_INSTANCE_ID> \
  --priv-launch-key tgw-lab-key.pem \
  --query 'PasswordData' \
  --output text \
  --region <REGION>
```

If the output is empty, the password is not yet available — wait 2 more minutes and retry.

---

## Connectivity Testing via SSM (If SSH Key Not Available)

If you cannot SSH directly, use SSM Session Manager:

```bash
# Start session into A2 (Linux)
aws ssm start-session \
  --target <A2_INSTANCE_ID> \
  --region <REGION>

# Run a command on an instance without SSH
aws ssm send-command \
  --instance-ids <INSTANCE_ID> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["curl -s -o /dev/null -w \"%{http_code}\" http://<TARGET_IP>"]' \
  --query 'Command.CommandId' \
  --output text \
  --region <REGION>

# Get result (wait ~10 seconds first)
aws ssm get-command-invocation \
  --command-id <COMMAND_ID> \
  --instance-id <INSTANCE_ID> \
  --query '[StandardOutputContent,StandardErrorContent]' \
  --output text \
  --region <REGION>
```

Note: SSM requires the instance to have an IAM instance profile with `AmazonSSMManagedInstanceCore`.
This lab does not include that by default — flag if needed.

---

## Cost Monitoring

Check current running costs for lab resources:

```bash
# List running instances and their types
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=lab-*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].{Name:Tags[?Key==`Name`]|[0].Value,Type:InstanceType,State:State.Name}' \
  --output table \
  --region <REGION>

# List TGWs (each costs $0.05/hr)
aws ec2 describe-transit-gateways \
  --filters "Name=tag:Name,Values=lab-tgw*" \
  --query 'TransitGateways[*].{Name:Tags[?Key==`Name`]|[0].Value,State:State}' \
  --output table \
  --region <REGION>
```

Remind user to run `terraform destroy` when lab is complete.

---

## Useful Filters Reference

| Goal | Filter syntax |
|---|---|
| All lab resources | `Name=tag:Name,Values=lab-*` |
| Running instances only | `Name=instance-state-name,Values=running` |
| Available TGW attachments | `Name=state,Values=available` |
| Active TGW routes | `Name=state,Values=active` |
| Specific VPC's route tables | `Name=vpc-id,Values=<VPC_ID>` |
| Subnet's NACL | `Name=association.subnet-id,Values=<SUBNET_ID>` |

## 2026-04-03 - Architecture refactor destroy count expectations

- A full per-VPC to per-subnet NACL refactor can legitimately destroy about 100 `aws_network_acl_rule` resources. Do not treat that raw count by itself as a failure condition.
- When reviewing a large refactor, base the stop/go call on resource types. High `aws_network_acl_rule` churn can be expected, but destroys or replacements touching `aws_vpc`, `aws_ec2_transit_gateway`, or `aws_ec2_transit_gateway_vpc_attachment` still require an immediate operator stop and review.

## 2026-04-04 - Direct private-IP validation after NLB removal

- Internal `NLB-B` and `NLB-C` were removed from the lab. Do not use their old DNS names as the primary validation path.
- From VPC-A, validate directly against:
  - `B1` mgmt: `10.1.3.10`
  - `C1` portal: `10.2.2.10`
  - `C2` gateway: `10.2.3.10`
  - `C3` controller: `10.2.4.10`
- `D1` at `10.3.1.10` must remain unreachable from VPC-A.
- The A2 diagnostic role does not include `ec2:SearchTransitGatewayRoutes`. If that command fails on A2, treat it as an IAM limitation, not automatic proof of a broken TGW route.
