# Phase 1 Part 3 — CLI Spike: Verification and NACL/SG Fixes
# Model 2+3: Centralized Egress + East-West Inspection
# Run AFTER Part 2 association cutover is complete.
# Goal: confirm inspection path is working, fix any NACL/SG gaps.

## MANDATORY FIRST STEPS

Re-load IDs if in a new shell session (same block as Part 2).

---

## PHASE 1G — Connectivity Verification

### Basic reachability from A2

```bash
# These must still work — routing now goes through VPC-B
ping -c 3 10.1.3.10   # B1 mgmt
ping -c 3 10.2.2.10   # C1 portal
ping -c 3 10.2.3.10   # C2 gateway
ping -c 3 10.2.4.10   # C3 controller

# TCP checks
nc -zv 10.1.3.10 443
nc -zv 10.2.2.10 443
nc -zv 10.2.3.10 443
nc -zv 10.2.4.10 443

# HTTP/S response codes
curl -sk -o /dev/null -w "B1  HTTPS: %{http_code}\n" https://10.1.3.10
curl -s  -o /dev/null -w "C1  HTTP:  %{http_code}\n" http://10.2.2.10
curl -sk -o /dev/null -w "C1  HTTPS: %{http_code}\n" https://10.2.2.10
curl -sk -o /dev/null -w "C2  HTTPS: %{http_code}\n" https://10.2.3.10
curl -sk -o /dev/null -w "C3  HTTPS: %{http_code}\n" https://10.2.4.10

# D1 must still fail from A2
curl -s --connect-timeout 5 -o /dev/null -w "D1  HTTP:  %{http_code}\n" http://10.3.1.10
```

Expected: all VPC-B and VPC-C targets return 200, D1 times out.

### Confirm VPC-B is in the inspection path (tcpdump test)

Run this from A2. It SSHes to B1 and starts a tcpdump while A2 sends traffic to C1.
If B1 sees the traffic, inspection is working. If B1 sees nothing, traffic is bypassing VPC-B.

```bash
KEY_PATH="/home/ec2-user/tgw-lab-key.pem"

# Start tcpdump on B1 in background
ssh -i $KEY_PATH -o StrictHostKeyChecking=no -o BatchMode=yes \
  ec2-user@10.1.3.10 \
  "sudo timeout 15 tcpdump -i any host 10.2.2.10 -n 2>/dev/null" &
TCPDUMP_PID=$!

# Wait for tcpdump to start, then send traffic
sleep 3
for i in $(seq 1 5); do
  curl -sk https://10.2.2.10 -o /dev/null
  sleep 1
done

wait $TCPDUMP_PID
```

Expected: tcpdump output shows packets with 10.2.2.10 as source or destination.
If output is empty: VPC-B is NOT in the path — check Spoke RT default route and associations.

### Asymmetry test — appliance mode validation

10 consecutive requests must all succeed. Any intermittent failure means
appliance mode is not working and return traffic is hitting the wrong ENI.

```bash
PASS=0; FAIL=0
for i in $(seq 1 10); do
  CODE=$(curl -sk https://10.2.2.10 -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
  if [ "$CODE" = "200" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "Request $i FAILED: $CODE"
  fi
done
echo "Result: $PASS/10 passed, $FAIL/10 failed"
```

Expected: 10/10 passed.
If intermittent failures: verify appliance mode is enabled on VPC-B attachments.

---

## PHASE 1H — NACL Fixes for Transit Traffic

VPC-B now sees ALL inter-VPC traffic as transit. The existing NACLs were written
for direct flows only. The following gaps are expected and must be fixed.

### nacl-b-trust — needs to allow transit traffic from all spoke CIDRs

VPC-B trust subnet is the TGW attachment point. All spoke traffic enters here.
Current rules only allow from 10.0.0.0/16 and 10.2.0.0/16.
Need to allow from all spoke CIDRs in both directions.

```bash
NACL_B_TRUST=$(aws ec2 describe-network-acls \
  --filters "Name=tag:Name,Values=nacl-b-trust" \
  --query "NetworkAcls[0].NetworkAclId" \
  --output text --region us-east-1)

# Check current rules
aws ec2 describe-network-acls --network-acl-ids $NACL_B_TRUST \
  --query "NetworkAcls[0].Entries[].{rule:RuleNumber,egress:Egress,proto:Protocol,cidr:CidrBlock,from:PortRange.From,to:PortRange.To,action:RuleAction}" \
  --output table --region us-east-1

# Add ingress: all TCP from VPC-D (transit traffic arriving from TGW2 via VPC-B)
aws ec2 create-network-acl-entry \
  --network-acl-id $NACL_B_TRUST --ingress \
  --rule-number 87 --protocol tcp \
  --cidr-block 10.3.0.0/16 \
  --port-range From=0,To=65535 \
  --rule-action allow --region us-east-1

# Add egress: all TCP to VPC-D (return path)
aws ec2 create-network-acl-entry \
  --network-acl-id $NACL_B_TRUST --egress \
  --rule-number 87 --protocol tcp \
  --cidr-block 10.3.0.0/16 \
  --port-range From=0,To=65535 \
  --rule-action allow --region us-east-1

# Add ICMP from VPC-D
aws ec2 create-network-acl-entry \
  --network-acl-id $NACL_B_TRUST --ingress \
  --rule-number 88 --protocol 1 \
  --cidr-block 10.3.0.0/16 \
  --icmp-type-code Code=-1,Type=-1 \
  --rule-action allow --region us-east-1
```

### nacl-c-dmz — needs to allow return traffic from VPC-D via VPC-B

C1 traffic returning to D1 exits through c-dmz. The NACL needs egress to 10.3.0.0/16.
(These were added in the connectivity fix session — verify they still exist.)

```bash
NACL_C_DMZ=$(aws ec2 describe-network-acls \
  --filters "Name=tag:Name,Values=nacl-c-dmz" \
  --query "NetworkAcls[0].NetworkAclId" \
  --output text --region us-east-1)

# Verify rule 107 exists (egress 443 to 10.3.0.0/16)
aws ec2 describe-network-acls --network-acl-ids $NACL_C_DMZ \
  --query "NetworkAcls[0].Entries[?RuleNumber==\`107\`]" \
  --output table --region us-east-1
# If missing, add it:
# aws ec2 create-network-acl-entry --network-acl-id $NACL_C_DMZ --egress \
#   --rule-number 107 --protocol tcp --cidr-block 10.3.0.0/16 \
#   --port-range From=443,To=443 --rule-action allow --region us-east-1
```

---

## PHASE 1I — Security Group Fixes for Transit Traffic

VPC-B SGs need to allow traffic that is now transiting through them.

### lab-sg-palo-trust — needs to allow all spoke CIDRs

```bash
SG_PALO_TRUST=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=lab-sg-palo-trust" \
  --query "SecurityGroups[0].GroupId" \
  --output text --region us-east-1)

# Check current rules
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$SG_PALO_TRUST" \
  --query "SecurityGroupRules[].[IsEgress,IpProtocol,FromPort,ToPort,CidrIpv4]" \
  --output table --region us-east-1

# Add ingress from VPC-D (transit traffic)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_PALO_TRUST \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":0,"ToPort":65535,"IpRanges":[{"CidrIp":"10.3.0.0/16","Description":"Transit from VPC-D"}]}]' \
  --region us-east-1

# Add egress to VPC-D (return path)
aws ec2 authorize-security-group-egress \
  --group-id $SG_PALO_TRUST \
  --ip-permissions '[{"IpProtocol":"tcp","FromPort":0,"ToPort":65535,"IpRanges":[{"CidrIp":"10.3.0.0/16","Description":"Return to VPC-D"}]}]' \
  --region us-east-1
```

---

## PHASE 1J — Full Reachability Analyzer Validation

Run the same 8-path check used in the original connectivity session.
The key new check is confirming VPC-B is in every path.

```bash
# Create paths for all required flows
A2_ENI="eni-0f098d4f5f0caa784"
A1_ENI="eni-0c2b86e85db72b3e5"
C1_ENI="eni-0ba00a418fb5801e3"
D1_ENI="eni-046e57eb6737beee4"
B1_MGMT_ENI="eni-0d06a24e8a84c0b68"

# A2 → C1 HTTPS (must transit VPC-B)
NIP_A2_C1=$(aws ec2 create-network-insights-path \
  --source $A2_ENI --destination $C1_ENI \
  --destination-ip 10.2.2.10 --protocol tcp --destination-port 443 \
  --tag-specifications "ResourceType=network-insights-path,Tags=[{Key=Name,Value=v3-a2-to-c1-443}]" \
  --query "NetworkInsightsPath.NetworkInsightsPathId" \
  --output text --region us-east-1)

# D1 → C1 HTTPS (must transit VPC-B via TGW2)
NIP_D1_C1=$(aws ec2 create-network-insights-path \
  --source $D1_ENI --destination $C1_ENI \
  --destination-ip 10.2.2.10 --protocol tcp --destination-port 443 \
  --tag-specifications "ResourceType=network-insights-path,Tags=[{Key=Name,Value=v3-d1-to-c1-443}]" \
  --query "NetworkInsightsPath.NetworkInsightsPathId" \
  --output text --region us-east-1)

# A2 → D1 (must still be blocked)
NIP_A2_D1=$(aws ec2 create-network-insights-path \
  --source $A2_ENI --destination $D1_ENI \
  --destination-ip 10.3.1.10 --protocol tcp --destination-port 22 \
  --tag-specifications "ResourceType=network-insights-path,Tags=[{Key=Name,Value=v3-a2-to-d1-blocked}]" \
  --query "NetworkInsightsPath.NetworkInsightsPathId" \
  --output text --region us-east-1)

# Start all analyses
for NIP in $NIP_A2_C1 $NIP_D1_C1 $NIP_A2_D1; do
  aws ec2 start-network-insights-analysis \
    --network-insights-path-id $NIP \
    --query "NetworkInsightsAnalysis.NetworkInsightsAnalysisId" \
    --output text --region us-east-1
done

# Wait and poll
sleep 20
aws ec2 describe-network-insights-analyses \
  --filters "Name=network-insights-path-id,Values=$NIP_A2_C1,$NIP_D1_C1,$NIP_A2_D1" \
  --query "NetworkInsightsAnalyses[].[NetworkInsightsPathId,Status,NetworkPathFound]" \
  --output table --region us-east-1
```

Expected:
- A2 → C1: True (path found, transiting VPC-B)
- D1 → C1: True (path found, transiting VPC-B via TGW2)
- A2 → D1: False (blocked — VPC-A has no route to VPC-D)

Clean up after:
```bash
for NIP in $NIP_A2_C1 $NIP_D1_C1 $NIP_A2_D1; do
  # Get analysis IDs and delete them first, then delete paths
  ANIA=$(aws ec2 describe-network-insights-analyses \
    --filters "Name=network-insights-path-id,Values=$NIP" \
    --query "NetworkInsightsAnalyses[].NetworkInsightsAnalysisId" \
    --output text --region us-east-1)
  for A in $ANIA; do
    aws ec2 delete-network-insights-analysis \
      --network-insights-analysis-id $A --region us-east-1
  done
  aws ec2 delete-network-insights-path \
    --network-insights-path-id $NIP --region us-east-1
done
```

---

## PHASE 1K — Write Spike Results Report

Save results to: artifacts/results/model23-cli-spike-YYYY-MM-DD.md

Include:
- All 4 new RT IDs
- All 6 attachment IDs
- Appliance mode confirmation
- Association state for all 4 new RTs
- Connectivity test results (pass/fail per path)
- tcpdump inspection path confirmation
- Asymmetry test result (X/10)
- Any NACL or SG fixes applied with rule numbers
- Any unexpected failures and how they were resolved

This report is the input to Phase 2 Terraform codification.

---

## STOP POINT

Before handing off to Phase 2, confirm:
- [ ] All connectivity tests pass (200 from B1, C1, C2, C3)
- [ ] D1 is still unreachable from A2
- [ ] tcpdump confirms VPC-B is in the path
- [ ] Asymmetry test: 10/10
- [ ] Reachability Analyzer: A2→C1 True, D1→C1 True, A2→D1 False
- [ ] Spike results report written to artifacts/results/
