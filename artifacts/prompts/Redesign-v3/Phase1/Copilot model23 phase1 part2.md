# Phase 1 Part 2 — CLI Spike: Association Cutover
# Model 2+3: Centralized Egress + East-West Inspection
# Run AFTER Part 1 is fully verified and current connectivity is confirmed healthy.
# This is the moment of truth — brief per-TGW outage during association swap.

## MANDATORY FIRST STEPS

Confirm Part 1 is complete before starting:
```bash
# All 4 new RTs must exist
aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Project,Values=tgw-segmentation-lab" \
  --query "TransitGatewayRouteTables[].[Tags[?Key=='Name'].Value|[0],State]" \
  --output table --region us-east-1

# Appliance mode must be enabled on both VPC-B attachments
aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=*attach-vpc-b*" \
  --query "TransitGatewayVpcAttachments[].[Tags[?Key=='Name'].Value|[0],Options.ApplianceModeSupport]" \
  --output table --region us-east-1

# Current connectivity must be healthy
# Run from A2: bash ~/netcheck.sh
```

Re-capture all IDs from Part 1 if running in a new shell session:
```bash
TGW1_SPOKE_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw1-rt-spoke" \
  --query "TransitGatewayRouteTables[0].TransitGatewayRouteTableId" \
  --output text --region us-east-1)

TGW1_FW_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw1-rt-firewall" \
  --query "TransitGatewayRouteTables[0].TransitGatewayRouteTableId" \
  --output text --region us-east-1)

TGW2_SPOKE_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw2-rt-spoke" \
  --query "TransitGatewayRouteTables[0].TransitGatewayRouteTableId" \
  --output text --region us-east-1)

TGW2_FW_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw2-rt-firewall" \
  --query "TransitGatewayRouteTables[0].TransitGatewayRouteTableId" \
  --output text --region us-east-1)

TGW1_OLD_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw1-rt-mgmt" \
  --query "TransitGatewayRouteTables[0].TransitGatewayRouteTableId" \
  --output text --region us-east-1)

TGW2_OLD_RT=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:Name,Values=tgw2-rt-customer" \
  --query "TransitGatewayRouteTables[0].TransitGatewayRouteTableId" \
  --output text --region us-east-1)

ATTACH_TGW1_A=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw1-attach-vpc-a" \
  --query "TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId" \
  --output text --region us-east-1)

ATTACH_TGW1_B=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw1-attach-vpc-b" \
  --query "TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId" \
  --output text --region us-east-1)

ATTACH_TGW1_C=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw1-attach-vpc-c" \
  --query "TransitGatewayVpcAttachments[0].TransitGatewayAttachmentId" \
  --output text --region us-east-1)

ATTACH_TGW2_B=$(aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=tgw2-attach-vpc-b" \
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

echo "All IDs loaded. Verify before proceeding:"
echo "TGW1_SPOKE_RT=$TGW1_SPOKE_RT"
echo "TGW1_FW_RT=$TGW1_FW_RT"
echo "TGW2_SPOKE_RT=$TGW2_SPOKE_RT"
echo "TGW2_FW_RT=$TGW2_FW_RT"
echo "TGW1_OLD_RT=$TGW1_OLD_RT"
echo "TGW2_OLD_RT=$TGW2_OLD_RT"
```

---

## PHASE 1D — TGW1 Association Cutover

There is no atomic swap. Each attachment must be disassociated then re-associated.
There is a ~15-30 second gap per attachment where it has no association.
Plan this for a maintenance window or low-traffic period.

Do TGW1 first. TGW2 traffic is unaffected during TGW1 cutover.

### TGW1: VPC-A → Spoke RT

```bash
# Disassociate VPC-A from old RT
aws ec2 disassociate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW1_A \
  --transit-gateway-route-table-id $TGW1_OLD_RT \
  --region us-east-1

# Wait for disassociation to complete
echo "Waiting 20s for disassociation..."
sleep 20

# Verify disassociated
aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW1_OLD_RT \
  --query "Associations[?TransitGatewayAttachmentId=='$ATTACH_TGW1_A'].State" \
  --output text --region us-east-1
# Expected: empty or "disassociated"

# Associate VPC-A with Spoke RT
aws ec2 associate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW1_A \
  --transit-gateway-route-table-id $TGW1_SPOKE_RT \
  --region us-east-1

sleep 10

# Verify associated
aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW1_SPOKE_RT \
  --query "Associations[?TransitGatewayAttachmentId=='$ATTACH_TGW1_A'].State" \
  --output text --region us-east-1
# Expected: associated
```

### TGW1: VPC-B → Firewall RT

```bash
aws ec2 disassociate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW1_B \
  --transit-gateway-route-table-id $TGW1_OLD_RT \
  --region us-east-1

sleep 20

aws ec2 associate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW1_B \
  --transit-gateway-route-table-id $TGW1_FW_RT \
  --region us-east-1

sleep 10

aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW1_FW_RT \
  --query "Associations[?TransitGatewayAttachmentId=='$ATTACH_TGW1_B'].State" \
  --output text --region us-east-1
```

### TGW1: VPC-C → Spoke RT

```bash
aws ec2 disassociate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW1_C \
  --transit-gateway-route-table-id $TGW1_OLD_RT \
  --region us-east-1

sleep 20

aws ec2 associate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW1_C \
  --transit-gateway-route-table-id $TGW1_SPOKE_RT \
  --region us-east-1

sleep 10

aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW1_SPOKE_RT \
  --query "Associations[?TransitGatewayAttachmentId=='$ATTACH_TGW1_C'].State" \
  --output text --region us-east-1
```

### Verify TGW1 cutover complete

```bash
echo "=== TGW1 Spoke RT associations ===" && \
aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW1_SPOKE_RT \
  --query "Associations[].[TransitGatewayAttachmentId,ResourceId,State]" \
  --output table --region us-east-1

echo "=== TGW1 Firewall RT associations ===" && \
aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW1_FW_RT \
  --query "Associations[].[TransitGatewayAttachmentId,ResourceId,State]" \
  --output table --region us-east-1
```

Expected:
- Spoke RT: VPC-A attachment + VPC-C attachment, both associated
- Firewall RT: VPC-B attachment, associated

---

## PHASE 1E — TGW2 Association Cutover

Same pattern as TGW1. VPC-D → Spoke RT, VPC-B → Firewall RT, VPC-C → Spoke RT.

### TGW2: VPC-D → Spoke RT

```bash
aws ec2 disassociate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW2_D \
  --transit-gateway-route-table-id $TGW2_OLD_RT \
  --region us-east-1

sleep 20

aws ec2 associate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW2_D \
  --transit-gateway-route-table-id $TGW2_SPOKE_RT \
  --region us-east-1

sleep 10

aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW2_SPOKE_RT \
  --query "Associations[?TransitGatewayAttachmentId=='$ATTACH_TGW2_D'].State" \
  --output text --region us-east-1
```

### TGW2: VPC-B → Firewall RT

```bash
aws ec2 disassociate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW2_B \
  --transit-gateway-route-table-id $TGW2_OLD_RT \
  --region us-east-1

sleep 20

aws ec2 associate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW2_B \
  --transit-gateway-route-table-id $TGW2_FW_RT \
  --region us-east-1

sleep 10

aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW2_FW_RT \
  --query "Associations[?TransitGatewayAttachmentId=='$ATTACH_TGW2_B'].State" \
  --output text --region us-east-1
```

### TGW2: VPC-C → Spoke RT

```bash
aws ec2 disassociate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW2_C \
  --transit-gateway-route-table-id $TGW2_OLD_RT \
  --region us-east-1

sleep 20

aws ec2 associate-transit-gateway-route-table \
  --transit-gateway-attachment-id $ATTACH_TGW2_C \
  --transit-gateway-route-table-id $TGW2_SPOKE_RT \
  --region us-east-1

sleep 10

aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW2_SPOKE_RT \
  --query "Associations[?TransitGatewayAttachmentId=='$ATTACH_TGW2_C'].State" \
  --output text --region us-east-1
```

### Verify TGW2 cutover complete

```bash
echo "=== TGW2 Spoke RT associations ===" && \
aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW2_SPOKE_RT \
  --query "Associations[].[TransitGatewayAttachmentId,ResourceId,State]" \
  --output table --region us-east-1

echo "=== TGW2 Firewall RT associations ===" && \
aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id $TGW2_FW_RT \
  --query "Associations[].[TransitGatewayAttachmentId,ResourceId,State]" \
  --output table --region us-east-1
```

---

## PHASE 1F — VPC-B Internal Route Table Update

VPC-B now receives all inter-VPC traffic. It needs a route back to TGW1 for
internet egress (VPC-D traffic arriving via TGW2 must exit via TGW1 → VPC-A NAT).

```bash
# Get VPC-B trust route table
RT_B_TRUST=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=lab-rt-b-trust" \
  --query "RouteTables[0].RouteTableId" \
  --output text --region us-east-1)

TGW1_ID=$(aws ec2 describe-transit-gateways \
  --filters "Name=tag:Name,Values=lab-tgw1-mgmt" \
  --query "TransitGateways[0].TransitGatewayId" \
  --output text --region us-east-1)

# Check if 0.0.0.0/0 already exists in b-trust
aws ec2 describe-route-tables --route-table-ids $RT_B_TRUST \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0']" \
  --output table --region us-east-1

# If missing, add it
aws ec2 create-route \
  --route-table-id $RT_B_TRUST \
  --destination-cidr-block 0.0.0.0/0 \
  --transit-gateway-id $TGW1_ID \
  --region us-east-1
```

---

## STOP POINT

Before proceeding to Part 3 (verification), confirm:
- [ ] TGW1 Spoke RT: VPC-A and VPC-C associated
- [ ] TGW1 Firewall RT: VPC-B associated
- [ ] TGW2 Spoke RT: VPC-D and VPC-C associated
- [ ] TGW2 Firewall RT: VPC-B associated
- [ ] VPC-B trust route table has 0.0.0.0/0 → TGW1
