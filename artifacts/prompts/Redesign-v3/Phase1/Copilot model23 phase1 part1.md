# Phase 1 Part 1 — CLI Spike: Two-Table TGW Pattern
# Model 2+3: Centralized Egress + East-West Inspection
# Run BEFORE touching Terraform. Validate the routing pattern live first.
# Date: run this on the day you execute it

## MANDATORY FIRST STEPS

Read these files before starting:
  C:\Users\Willi\projects\Labs\artifacts\skills\terraform-skill.md
  C:\Users\Willi\projects\Labs\artifacts\skills\aws-cli-skill.md
  C:\Users\Willi\projects\Labs\artifacts\prompts\copilot-instructions-v1.md

Confirm AWS identity and capture current TGW state before making any changes:

```bash
aws sts get-caller-identity --region us-east-1

# Capture current TGW IDs
aws ec2 describe-transit-gateways \
  --filters "Name=tag:Name,Values=lab-tgw*" \
  --query "TransitGateways[].[Tags[?Key=='Name'].Value|[0],TransitGatewayId,State]" \
  --output table --region us-east-1

# Capture current TGW route tables
aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw*-rt-*" \
  --query "TransitGatewayRouteTables[].[Tags[?Key=='Name'].Value|[0],TransitGatewayRouteTableId,State]" \
  --output table --region us-east-1

# Capture current TGW attachments
aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw*-attach-*" "Name=state,Values=available" \
  --query "TransitGatewayVpcAttachments[].[Tags[?Key=='Name'].Value|[0],TransitGatewayAttachmentId,TransitGatewayId,Options.ApplianceModeSupport]" \
  --output table --region us-east-1
```

Record the IDs. You will need them throughout this spike.

Expected current state:
- TGW1: lab-tgw1-mgmt       — one RT: tgw1-rt-mgmt
- TGW2: lab-tgw2-customer   — one RT: tgw2-rt-customer
- 6 attachments, appliance mode disabled on all

---

## PHASE 1A — Create New Route Tables (additive, zero impact)

These are new resources. Nothing is associated yet. No traffic is affected.

```bash
# TGW1 Spoke RT — will hold VPC-A, VPC-C
TGW1_ID=$(aws ec2 describe-transit-gateways \
  --filters "Name=tag:Name,Values=lab-tgw1-mgmt" \
  --query "TransitGateways[0].TransitGatewayId" \
  --output text --region us-east-1)

TGW1_SPOKE_RT=$(aws ec2 create-transit-gateway-route-table \
  --transit-gateway-id $TGW1_ID \
  --tag-specifications "ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=tgw1-rt-spoke},{Key=Role,Value=spoke},{Key=Project,Value=tgw-segmentation-lab}]" \
  --query "TransitGatewayRouteTable.TransitGatewayRouteTableId" \
  --output text --region us-east-1)
echo "TGW1 Spoke RT: $TGW1_SPOKE_RT"

# TGW1 Firewall RT — will hold VPC-B (inspection VPC)
TGW1_FW_RT=$(aws ec2 create-transit-gateway-route-table \
  --transit-gateway-id $TGW1_ID \
  --tag-specifications "ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=tgw1-rt-firewall},{Key=Role,Value=firewall},{Key=Project,Value=tgw-segmentation-lab}]" \
  --query "TransitGatewayRouteTable.TransitGatewayRouteTableId" \
  --output text --region us-east-1)
echo "TGW1 Firewall RT: $TGW1_FW_RT"

# TGW2 Spoke RT — will hold VPC-D
TGW2_ID=$(aws ec2 describe-transit-gateways \
  --filters "Name=tag:Name,Values=lab-tgw2-customer" \
  --query "TransitGateways[0].TransitGatewayId" \
  --output text --region us-east-1)

TGW2_SPOKE_RT=$(aws ec2 create-transit-gateway-route-table \
  --transit-gateway-id $TGW2_ID \
  --tag-specifications "ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=tgw2-rt-spoke},{Key=Role,Value=spoke},{Key=Project,Value=tgw-segmentation-lab}]" \
  --query "TransitGatewayRouteTable.TransitGatewayRouteTableId" \
  --output text --region us-east-1)
echo "TGW2 Spoke RT: $TGW2_SPOKE_RT"

# TGW2 Firewall RT — will hold VPC-B on TGW2
TGW2_FW_RT=$(aws ec2 create-transit-gateway-route-table \
  --transit-gateway-id $TGW2_ID \
  --tag-specifications "ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=tgw2-rt-firewall},{Key=Role,Value=firewall},{Key=Project,Value=tgw-segmentation-lab}]" \
  --query "TransitGatewayRouteTable.TransitGatewayRouteTableId" \
  --output text --region us-east-1)
echo "TGW2 Firewall RT: $TGW2_FW_RT"
```

Verify all 4 were created:
```bash
aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Project,Values=tgw-segmentation-lab" \
  --query "TransitGatewayRouteTables[].[Tags[?Key=='Name'].Value|[0],TransitGatewayRouteTableId,State]" \
  --output table --region us-east-1
```

Expected: 6 route tables total (2 old + 4 new), all in state `available`.

---

## PHASE 1B — Enable Appliance Mode on VPC-B Attachments (no outage)

Appliance mode is required for stateful inspection. Without it, return traffic may
arrive at a different ENI than forward traffic and the firewall drops it as unknown.

This is a modify operation — no destroy, no outage.

```bash
# Get VPC-B attachment IDs
ATTACH_TGW1_B=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw1-attach-vpc-b" \
  --query "TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId" \
  --output text --region us-east-1)

ATTACH_TGW2_B=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw2-attach-vpc-b" \
  --query "TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId" \
  --output text --region us-east-1)

echo "TGW1 VPC-B attachment: $ATTACH_TGW1_B"
echo "TGW2 VPC-B attachment: $ATTACH_TGW2_B"

# Enable appliance mode
aws ec2 modify-transit-gateway-vpc-attachment \
  --transit-gateway-attachment-id $ATTACH_TGW1_B \
  --options ApplianceModeSupport=enable \
  --region us-east-1

aws ec2 modify-transit-gateway-vpc-attachment \
  --transit-gateway-attachment-id $ATTACH_TGW2_B \
  --options ApplianceModeSupport=enable \
  --region us-east-1
```

Verify:
```bash
aws ec2 describe-transit-gateway-vpc-attachments \
  --transit-gateway-attachment-ids $ATTACH_TGW1_B $ATTACH_TGW2_B \
  --query "TransitGatewayVpcAttachments[].[Tags[?Key=='Name'].Value|[0],Options.ApplianceModeSupport,State]" \
  --output table --region us-east-1
```

Expected: both show `enable` for ApplianceModeSupport.

---

## PHASE 1C — Populate New Route Tables (additive, zero impact)

Routes in unassociated route tables have no effect on traffic. Safe to add now.

```bash
# Collect remaining attachment IDs
ATTACH_TGW1_A=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw1-attach-vpc-a" \
  --query "TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId" \
  --output text --region us-east-1)

ATTACH_TGW1_C=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw1-attach-vpc-c" \
  --query "TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId" \
  --output text --region us-east-1)

ATTACH_TGW2_C=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw2-attach-vpc-c" \
  --query "TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId" \
  --output text --region us-east-1)

ATTACH_TGW2_D=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw2-attach-vpc-d" \
  --query "TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId" \
  --output text --region us-east-1)

echo "TGW1-A: $ATTACH_TGW1_A"
echo "TGW1-C: $ATTACH_TGW1_C"
echo "TGW2-C: $ATTACH_TGW2_C"
echo "TGW2-D: $ATTACH_TGW2_D"

# ── TGW1 Spoke RT ─────────────────────────────────────────────────────────
# Default route → VPC-B (forces all spoke traffic through inspection)
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 0.0.0.0/0 \
  --transit-gateway-attachment-id $ATTACH_TGW1_B \
  --transit-gateway-route-table-id $TGW1_SPOKE_RT \
  --region us-east-1

# ── TGW1 Firewall RT ──────────────────────────────────────────────────────
# Specific routes back to each spoke after inspection
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.0.0.0/16 \
  --transit-gateway-attachment-id $ATTACH_TGW1_A \
  --transit-gateway-route-table-id $TGW1_FW_RT \
  --region us-east-1

aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.2.0.0/16 \
  --transit-gateway-attachment-id $ATTACH_TGW1_C \
  --transit-gateway-route-table-id $TGW1_FW_RT \
  --region us-east-1

# Default egress → VPC-A NAT GW (internet-bound traffic from VPC-B)
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 0.0.0.0/0 \
  --transit-gateway-attachment-id $ATTACH_TGW1_A \
  --transit-gateway-route-table-id $TGW1_FW_RT \
  --region us-east-1

# ── TGW2 Spoke RT ─────────────────────────────────────────────────────────
# Default route → VPC-B (forces VPC-D traffic through inspection)
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 0.0.0.0/0 \
  --transit-gateway-attachment-id $ATTACH_TGW2_B \
  --transit-gateway-route-table-id $TGW2_SPOKE_RT \
  --region us-east-1

# ── TGW2 Firewall RT ──────────────────────────────────────────────────────
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.1.0.0/16 \
  --transit-gateway-attachment-id $ATTACH_TGW2_B \
  --transit-gateway-route-table-id $TGW2_FW_RT \
  --region us-east-1

aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.2.0.0/16 \
  --transit-gateway-attachment-id $ATTACH_TGW2_C \
  --transit-gateway-route-table-id $TGW2_FW_RT \
  --region us-east-1

aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.3.0.0/16 \
  --transit-gateway-attachment-id $ATTACH_TGW2_D \
  --transit-gateway-route-table-id $TGW2_FW_RT \
  --region us-east-1

# Default egress → VPC-B → TGW1 → VPC-A NAT (VPC-D internet path)
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 0.0.0.0/0 \
  --transit-gateway-attachment-id $ATTACH_TGW2_B \
  --transit-gateway-route-table-id $TGW2_FW_RT \
  --region us-east-1
```

Verify all routes are populated:
```bash
echo "=== TGW1 Spoke RT ===" && \
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $TGW1_SPOKE_RT \
  --filters "Name=state,Values=active" \
  --query "Routes[].[DestinationCidrBlock,TransitGatewayAttachments[0].TransitGatewayAttachmentId,State]" \
  --output table --region us-east-1

echo "=== TGW1 Firewall RT ===" && \
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $TGW1_FW_RT \
  --filters "Name=state,Values=active" \
  --query "Routes[].[DestinationCidrBlock,TransitGatewayAttachments[0].TransitGatewayAttachmentId,State]" \
  --output table --region us-east-1

echo "=== TGW2 Spoke RT ===" && \
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $TGW2_SPOKE_RT \
  --filters "Name=state,Values=active" \
  --query "Routes[].[DestinationCidrBlock,TransitGatewayAttachments[0].TransitGatewayAttachmentId,State]" \
  --output table --region us-east-1

echo "=== TGW2 Firewall RT ===" && \
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $TGW2_FW_RT \
  --filters "Name=state,Values=active" \
  --query "Routes[].[DestinationCidrBlock,TransitGatewayAttachments[0].TransitGatewayAttachmentId,State]" \
  --output table --region us-east-1
```

Save the output to: artifacts/results/model23-cli-spike-YYYY-MM-DD.md

---

## STOP POINT

Before proceeding to Part 2 (the association cutover), confirm:
- [ ] All 4 new route tables exist and are available
- [ ] Appliance mode is enabled on both VPC-B attachments
- [ ] All route tables are populated with the correct routes
- [ ] Current connectivity is still working (run netcheck.sh from A2)

Do NOT proceed to Part 2 until all checks pass.
