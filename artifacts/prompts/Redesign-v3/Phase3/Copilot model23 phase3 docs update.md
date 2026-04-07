# Phase 3 — Update Docs, Scripts, and Skills: Model 2+3
# Run AFTER Phase 3 clean redeploy is confirmed working
# Date: YYYY-MM-DD (update when running)

## MANDATORY FIRST STEPS

Read these files before making any changes:
  C:\Users\Willi\projects\Labs\artifacts\skills\terraform-skill.md
  C:\Users\Willi\projects\Labs\artifacts\skills\aws-cli-skill.md
  C:\Users\Willi\projects\Labs\artifacts\skills\network-troubleshooting\SKILL.md
  C:\Users\Willi\projects\Labs\artifacts\copilot-instructions-v1.md
  C:\Users\Willi\projects\Labs\artifacts\results\model23-cli-spike-YYYY-MM-DD.md
  C:\Users\Willi\projects\Labs\artifacts\results\model23-phase2-terraform-YYYY-MM-DD.md

---

## TASK 1 — Update terraform-skill.md

Append this dated section:

## YYYY-MM-DD — Combined Model 2+3: Two-Table TGW Pattern

### The Two-Table Pattern
Every TGW needs TWO route tables for east-west inspection:
  Spoke RT: associated with all spoke VPCs (A, C, D)
    - Single route: 0.0.0.0/0 → VPC-B (inspection VPC)
    - Forces ALL inter-VPC traffic through inspection
  Firewall RT: associated with VPC-B (inspection VPC)
    - Specific routes back to each spoke VPC
    - Default route for internet egress via VPC-A

### Appliance Mode is Mandatory
For stateful inspection to work, enable appliance mode on
the inspection VPC attachment:
  appliance_mode_support = "enable"
Without this, asymmetric routing breaks stateful firewalls.
Return traffic may arrive at a different ENI than forward
traffic — firewall drops it as an unknown session.

### TGW Route Table Association Order
Cannot move an attachment between route tables atomically.
Must: disassociate → wait 15s → associate.
In Terraform, use depends_on to enforce this order or use
lifecycle { replace_triggered_by } to handle the swap.

### Import Order for Two-Table Pattern
When importing existing resources:
  1. Import route tables first
  2. Import associations second
  3. Import routes last
Routes depend on associations which depend on route tables.

### Firewall RT Default Route
The 0.0.0.0/0 in the Firewall RT points to VPC-A (egress VPC)
NOT to the internet. VPC-B does not have a direct IGW — it
relies on VPC-A's NAT GW for internet access. Traffic path:
  Spoke VPC → Spoke RT → VPC-B → Firewall RT → 0.0.0.0/0 → VPC-A → NAT

### VPC-D Internet Egress via TGW2
VPC-D has no path to VPC-A (no shared TGW). Internet egress
from VPC-D traverses:
  VPC-D → TGW2 → VPC-B → VPC-B route table → TGW1 → VPC-A → NAT
VPC-B's internal route table handles the TGW2→TGW1 handoff.
VPC-B needs route: 0.0.0.0/0 → TGW1 (for internet egress)

---

## TASK 2 — Update aws-cli-skill.md

Append this dated section:

## YYYY-MM-DD — TGW Two-Table CLI Commands

### Useful verification commands for two-table pattern:

```bash
# Verify which RT an attachment is associated with
aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id <RT_ID> \
  --query "Associations[*].{Attachment:TransitGatewayAttachmentId,State:State}" \
  --output table --region us-east-1

# Search routes in a specific RT
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <RT_ID> \
  --filters "Name=state,Values=active" \
  --output table --region us-east-1

# Verify appliance mode on an attachment
aws ec2 describe-transit-gateway-vpc-attachments \
  --transit-gateway-attachment-ids <ATTACH_ID> \
  --query "TransitGatewayVpcAttachments[0].Options.ApplianceModeSupport" \
  --output text --region us-east-1

# Verify traffic path by checking which RT a VPC is associated with
aws ec2 get-transit-gateway-route-table-associations \
  --transit-gateway-route-table-id <SPOKE_RT_ID> \
  --output table --region us-east-1
```

### ec2:SearchTransitGatewayRoutes IAM permission
Required on A2 diagnostic role for route verification.
Inline policy name: tgw-route-search
Actions needed:
  - ec2:SearchTransitGatewayRoutes
  - ec2:DescribeTransitGatewayRouteTables
  - ec2:GetTransitGatewayRouteTableAssociations
  - ec2:GetTransitGatewayRouteTablePropagations

---

## TASK 3 — Update network-troubleshooting SKILL.md

### Add new section: TOOL 10 — Two-Table Pattern Verifier

Append after the existing tools:

```markdown
### TOOL 10 — Two-Table TGW Pattern Verifier

When to use: After deploying combined Model 2+3 to confirm
all VPC-to-VPC traffic is forced through the inspection VPC.

Key checks:
1. Spoke VPCs are associated with Spoke RT (not Firewall RT)
2. Inspection VPC is associated with Firewall RT
3. Spoke RT has 0.0.0.0/0 → inspection VPC attachment
4. Firewall RT has specific routes to each spoke VPC
5. Appliance mode is enabled on inspection VPC attachment

Tcpdump verification (from B1, while A2 curls C1):
  sudo tcpdump -i any host 10.2.2.10 -n -c 10
  If B1 sees traffic: inspection is in the path ✅
  If B1 sees nothing: traffic is bypassing VPC-B ❌

Asymmetry test (10 consecutive requests, all must succeed):
  for i in $(seq 1 10); do
    curl -sk https://10.2.2.10 -o /dev/null -w "Request $i: %{http_code}\n"
  done
  Any intermittent failures = appliance mode not working
```

### Add new Known Issue:

```markdown
### Issue: TGW route table association swap causes brief outage
Symptom: 30-60 second connectivity loss when moving an
attachment from one route table to another.
Root cause: Must disassociate before associating — no atomic
swap. There is a gap where the attachment has no association.
Fix: Plan association changes for maintenance windows.
In Terraform: use lifecycle rules to control swap order.
```

---

## TASK 4 — Update netcheck.sh (Linux A2 script)

Add a new section to ~/netcheck.sh on A2 that verifies the
two-table pattern is working.

Find the file and add after SECTION 7 (AWS CLI checks):

```bash
# =============================================================================
# SECTION 8 — Two-Table Pattern Verification (Model 2+3)
# =============================================================================
header "SECTION 8 — Two-Table Inspection Path Verification"

log "Verifying VPC-B is in the traffic path (tcpdump test)"
info "Starting background tcpdump on B1 while sending traffic from A2"

if [ -f "$KEY_PATH" ]; then
    # Start tcpdump on B1 in background
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o BatchMode=yes \
        "ec2-user@$IP_PALO_MGMT" \
        "sudo timeout 10 tcpdump -i any host $IP_C1_PORTAL -n -c 5 2>/dev/null | head -5" &
    TCPDUMP_PID=$!

    # Send traffic from A2 to C1
    sleep 2
    curl -sk "https://$IP_C1_PORTAL" -o /dev/null -w "%{http_code}" 2>/dev/null

    # Wait for tcpdump to complete
    wait $TCPDUMP_PID
    TCPDUMP_OUTPUT=$(ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no \
        -o BatchMode=yes "ec2-user@$IP_PALO_MGMT" \
        "sudo timeout 5 tcpdump -i any host $IP_C1_PORTAL -n -c 3 2>/dev/null" 2>&1 || echo "")

    if echo "$TCPDUMP_OUTPUT" | grep -q "$IP_C1_PORTAL"; then
        pass "VPC-B (B1) sees traffic destined for C1 — inspection path confirmed"
    else
        fail "VPC-B (B1) does NOT see C1 traffic — traffic may be bypassing inspection"
        info "Check: Spoke RT association for VPC-A, Spoke RT default route → VPC-B"
    fi
else
    warn "Key not found — skipping tcpdump inspection path test"
fi

log "Asymmetry test — 10 consecutive requests (all must return 200)"
PASS_COUNT=0
FAIL_COUNT=0
for i in $(seq 1 10); do
    CODE=$(curl -sk "https://$IP_C1_PORTAL" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
    if [ "$CODE" = "200" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        warn "Request $i returned $CODE"
    fi
done

if [ "$FAIL_COUNT" -eq 0 ]; then
    pass "Asymmetry test: 10/10 requests succeeded — appliance mode working correctly"
else
    fail "Asymmetry test: $FAIL_COUNT/10 requests failed — check appliance_mode_support on VPC-B attachment"
fi
divider
```

To update the file on A2:
```bash
scp -i tgw-lab-key.pem netcheck.sh ec2-user@<A2_PUBLIC_IP>:~
sed -i 's/\r//' ~/netcheck.sh
chmod +x ~/netcheck.sh
```

---

## TASK 5 — Update netcheck.ps1 (PowerShell laptop script)

Add a new section to netcheck.ps1 that verifies the two-table
pattern from the operator laptop using AWS CLI.

Add after SECTION 8 (NACL verification):

```powershell
# =============================================================================
# SECTION 9 — Two-Table TGW Pattern Verification
# =============================================================================
Write-Header "SECTION 9 — Two-Table Inspection Pattern Verification"

Write-Check "Verifying Spoke RTs exist for TGW1 and TGW2"
$spokeRTs = aws ec2 describe-transit-gateway-route-tables --filters "Name=tag:Role,Values=spoke" --query "TransitGatewayRouteTables[*].{Name:Tags[?Key=='Name']|[0].Value,ID:TransitGatewayRouteTableId,State:State}" --output json --region $region 2>$null | ConvertFrom-Json
foreach ($rt in $spokeRTs) {
    if ($rt.State -eq "available") {
        Write-Pass "Spoke RT found: $($rt.Name) ($($rt.ID))"
    } else {
        Write-Fail "Spoke RT $($rt.Name) is in state: $($rt.State)"
    }
}

Write-Check "Verifying VPC-A is on Spoke RT (not Firewall RT)"
# Check that VPC-A attachment is associated with a Spoke RT
foreach ($rt in $spokeRTs) {
    $assocs = aws ec2 get-transit-gateway-route-table-associations --transit-gateway-route-table-id $rt.ID --output json --region $region 2>$null | ConvertFrom-Json
    $aAttach = $assocs.Associations | Where-Object { $_.ResourceId -eq (aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*vpc-a*" --query "Vpcs[0].VpcId" --output text --region $region 2>$null) }
    if ($aAttach) {
        Write-Pass "VPC-A is associated with Spoke RT $($rt.Name) — correct"
    }
}

Write-Check "Verifying Spoke RT has 0.0.0.0/0 → VPC-B"
foreach ($rt in $spokeRTs) {
    $defaultRoute = aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id $rt.ID --filters "Name=state,Values=active" --query "Routes[?DestinationCidrBlock=='0.0.0.0/0'].State" --output text --region $region 2>$null
    if ($defaultRoute -eq "active") {
        Write-Pass "Spoke RT $($rt.Name) has active default route → VPC-B"
    } else {
        Write-Fail "Spoke RT $($rt.Name) MISSING default route — traffic will not be forced through inspection"
    }
}

Write-Check "Verifying appliance mode on VPC-B attachments"
$bAttachments = aws ec2 describe-transit-gateway-vpc-attachments --filters "Name=tag:Name,Values=*attach-vpc-b*" --query "TransitGatewayVpcAttachments[*].{Name:Tags[?Key=='Name']|[0].Value,ID:TransitGatewayAttachmentId,Appliance:Options.ApplianceModeSupport}" --output json --region $region 2>$null | ConvertFrom-Json
foreach ($attach in $bAttachments) {
    if ($attach.Appliance -eq "enable") {
        Write-Pass "$($attach.Name) appliance mode: ENABLED"
    } else {
        Write-Fail "$($attach.Name) appliance mode: DISABLED — asymmetric routing risk"
    }
}
```

---

## TASK 6 — Update deploy.ps1

Add a new phase to deploy.ps1 between Phase 3 (apply) and
Phase 4 (wait for instances):

```powershell
# =============================================================================
# PHASE 3B — Verify Two-Table TGW Pattern Post-Apply
# =============================================================================
Write-Header "PHASE 3B — Two-Table Pattern Verification"

Write-Step "Verifying Spoke RTs are in place"
$spokeRTs = aws ec2 describe-transit-gateway-route-tables --filters "Name=tag:Role,Values=spoke" --query "TransitGatewayRouteTables[*].TransitGatewayRouteTableId" --output json --region $region 2>$null | ConvertFrom-Json
if ($spokeRTs.Count -eq 2) {
    Write-Pass "Both Spoke RTs exist ($($spokeRTs -join ', '))"
} else {
    Write-Fail "Expected 2 Spoke RTs, found $($spokeRTs.Count) — two-table pattern may not be deployed"
}

Write-Step "Verifying appliance mode on VPC-B attachments"
$bAttachments = aws ec2 describe-transit-gateway-vpc-attachments --filters "Name=tag:Name,Values=*attach-vpc-b*" --query "TransitGatewayVpcAttachments[*].Options.ApplianceModeSupport" --output json --region $region 2>$null | ConvertFrom-Json
$allEnabled = ($bAttachments | Where-Object { $_ -ne "enable" }).Count -eq 0
if ($allEnabled -and $bAttachments.Count -eq 2) {
    Write-Pass "Appliance mode enabled on both VPC-B attachments"
} else {
    Write-Fail "Appliance mode NOT enabled on all VPC-B attachments — fix before running connectivity tests"
}
```

---

## TASK 7 — Update teardown.ps1

Add cleanup for Model 2+3 resources before terraform destroy:

```powershell
# =============================================================================
# Model 2+3 Resources — delete before terraform destroy
# =============================================================================
Write-Step "Deleting Spoke RT routes before association removal"

$spokeRTs = aws ec2 describe-transit-gateway-route-tables --filters "Name=tag:Role,Values=spoke" --query "TransitGatewayRouteTables[*].TransitGatewayRouteTableId" --output json --region $region 2>$null | ConvertFrom-Json

foreach ($rtId in $spokeRTs) {
    # Delete default route from each Spoke RT
    aws ec2 delete-transit-gateway-route --transit-gateway-route-table-id $rtId --destination-cidr-block "0.0.0.0/0" --region $region 2>$null
    Write-Info "Deleted default route from Spoke RT $rtId"
}

Write-Step "Disabling appliance mode before attachment deletion"
$bAttachments = aws ec2 describe-transit-gateway-vpc-attachments --filters "Name=tag:Name,Values=*attach-vpc-b*" --query "TransitGatewayVpcAttachments[*].TransitGatewayAttachmentId" --output json --region $region 2>$null | ConvertFrom-Json

foreach ($attachId in $bAttachments) {
    aws ec2 modify-transit-gateway-vpc-attachment --transit-gateway-attachment-id $attachId --options ApplianceModeSupport=disable --region $region 2>$null
    Write-Info "Disabled appliance mode on $attachId"
}

Write-Step "Spoke RTs will be deleted by terraform destroy"
Write-Info "Route table associations and routes are managed by Terraform"
```

---

## TASK 8 — Write Completion Report

Save to: artifacts/results/model23-phase3-docs-update-YYYY-MM-DD.md

Include:
- Each file updated with summary of changes
- Any sections that could not be updated and why
- Confirmation that all scripts reflect the Model 2+3 architecture
- Next steps for the operator