# Task: Update teardown.ps1 — Add All Live Fixes and Post-Session Knowledge
# Date: 2026-04-04

## Context

The teardown.ps1 script destroys the TGW segmentation lab and
cleans up all AWS resources. During the 2026-04-04 troubleshooting
session, several resources were added manually via AWS CLI that
are NOT in Terraform state. These manual resources will NOT be
destroyed by terraform destroy and must be added to teardown.ps1.

Additionally, the teardown script needs a pre-flight check to
confirm what is about to be destroyed before executing.

DO NOT run terraform destroy or any destructive AWS CLI commands.
This task is script updates only.

---

## Step 1 — Read Existing Script

```powershell
Get-Content -Raw C:\Users\Willi\projects\Labs\teardown.ps1
```

Understand the current structure before making any changes.

---

## Step 2 — Read Context Files

Read these files to understand what was manually created:
  C:\Users\Willi\projects\Labs\artifacts\results\2026-04-04_skill-updates.md
  C:\Users\Willi\projects\Labs\artifacts\COPILOT-CODIFY-FIXES-2026-04-04.md

---

## Step 3 — Inventory Manual AWS Resources to Add

The following resources were created manually via AWS CLI and
are NOT tracked in Terraform state. They must be explicitly
deleted during teardown.

### Manual Routes Added to lab-rt-b-untrust
Route table ID: rtb-0e72a76ab0c661208
Routes added manually:
  - 10.0.0.0/16 → tgw-0182ba880fd0f5577
  - 10.2.0.0/16 → tgw-0182ba880fd0f5577
  - 10.3.0.0/16 → tgw-07ee4fdc98c23dcaa

Teardown command:
```powershell
aws ec2 delete-route --route-table-id rtb-0e72a76ab0c661208 --destination-cidr-block 10.0.0.0/16 --region us-east-1
aws ec2 delete-route --route-table-id rtb-0e72a76ab0c661208 --destination-cidr-block 10.2.0.0/16 --region us-east-1
aws ec2 delete-route --route-table-id rtb-0e72a76ab0c661208 --destination-cidr-block 10.3.0.0/16 --region us-east-1
```

### Manual NACL Rules Added to nacl-c-portal (acl-0c461e7c980d08c00)
Rules added manually:
  - Inbound 90:  TCP 80   from 10.0.0.0/16
  - Inbound 91:  TCP 443  from 10.0.0.0/16
  - Inbound 92:  TCP 22   from 10.0.0.0/16
  - Outbound 90: TCP 1024-65535 to 10.0.0.0/16

Teardown command:
```powershell
aws ec2 delete-network-acl-entry --network-acl-id acl-0c461e7c980d08c00 --rule-number 90 --ingress --region us-east-1
aws ec2 delete-network-acl-entry --network-acl-id acl-0c461e7c980d08c00 --rule-number 91 --ingress --region us-east-1
aws ec2 delete-network-acl-entry --network-acl-id acl-0c461e7c980d08c00 --rule-number 92 --ingress --region us-east-1
aws ec2 delete-network-acl-entry --network-acl-id acl-0c461e7c980d08c00 --rule-number 90 --egress --region us-east-1
```

### Manual NACL Rules Added to nacl-c-dmz (acl-045e906a514372224)
Rules added manually:
  - Outbound 96: TCP 80 to 10.2.2.0/24
  - Outbound 101: TCP 80 to 10.2.2.0/24

Teardown command:
```powershell
aws ec2 delete-network-acl-entry --network-acl-id acl-045e906a514372224 --rule-number 96 --egress --region us-east-1
aws ec2 delete-network-acl-entry --network-acl-id acl-045e906a514372224 --rule-number 101 --egress --region us-east-1
```

### Manual NACL Rules Added to nacl-a (acl-05413fc9ffa66da56)
Rules added manually:
  - Inbound 111: TCP 80   from 10.0.0.0/16
  - Inbound 112: TCP 443  from 10.0.0.0/16
  - Inbound 113: TCP 8443 from 10.0.0.0/16
  - Outbound 125: TCP 80  to 10.2.0.0/16

Teardown command:
```powershell
aws ec2 delete-network-acl-entry --network-acl-id acl-05413fc9ffa66da56 --rule-number 111 --ingress --region us-east-1
aws ec2 delete-network-acl-entry --network-acl-id acl-05413fc9ffa66da56 --rule-number 112 --ingress --region us-east-1
aws ec2 delete-network-acl-entry --network-acl-id acl-05413fc9ffa66da56 --rule-number 113 --ingress --region us-east-1
aws ec2 delete-network-acl-entry --network-acl-id acl-05413fc9ffa66da56 --rule-number 125 --egress --region us-east-1
```

### Manual Security Group Rule Added to C1 SG (sg-0c044168b47ec90bf)
Rules added manually:
  - Inbound TCP 80 from 10.0.0.0/16

Teardown command:
```powershell
$ruleId = aws ec2 describe-security-group-rules --filters "Name=group-id,Values=sg-0c044168b47ec90bf" --output json --region us-east-1 | ConvertFrom-Json | Select-Object -ExpandProperty SecurityGroupRules | Where-Object { $_.IsEgress -eq $false -and $_.FromPort -eq 80 -and $_.CidrIpv4 -eq "10.0.0.0/16" } | Select-Object -ExpandProperty SecurityGroupRuleId
aws ec2 revoke-security-group-ingress --group-id sg-0c044168b47ec90bf --security-group-rule-ids $ruleId --region us-east-1
```

### IAM Instance Profile Created for A2
Resources created manually:
  - IAM role: lab-a2-diagnostic-role
  - IAM instance profile: lab-a2-diagnostic-profile

Teardown commands (run in order):
```powershell
aws ec2 disassociate-iam-instance-profile --association-id (aws ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$(aws ec2 describe-instances --filters 'Name=tag:Name,Values=lab-a2-linux' --query 'Reservations[0].Instances[0].InstanceId' --output text --region us-east-1)" --query "IamInstanceProfileAssociations[0].AssociationId" --output text --region us-east-1) --region us-east-1
aws iam remove-role-from-instance-profile --instance-profile-name lab-a2-diagnostic-profile --role-name lab-a2-diagnostic-role
aws iam delete-instance-profile --instance-profile-name lab-a2-diagnostic-profile
aws iam detach-role-policy --role-name lab-a2-diagnostic-role --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
aws iam detach-role-policy --role-name lab-a2-diagnostic-role --policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly
aws iam detach-role-policy --role-name lab-a2-diagnostic-role --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam delete-role --role-name lab-a2-diagnostic-role
```

---

## Step 4 — Update teardown.ps1

Rewrite the teardown.ps1 script with this structure:

### Section 0 — Pre-flight Inventory
Before destroying anything, print a summary of what will be
destroyed. This gives the operator a chance to abort.

```
=== TGW LAB TEARDOWN PRE-FLIGHT ===
Date: <current date>

The following will be destroyed:

TERRAFORM MANAGED:
  [list key resources from terraform state list]

MANUAL (non-Terraform):
  - lab-rt-b-untrust: 3 manual routes
  - nacl-c-portal: 4 manual NACL entries
  - nacl-c-dmz: 2 manual NACL entries
  - nacl-a: 4 manual NACL entries
  - C1 SG: 1 manual inbound rule
  - IAM: lab-a2-diagnostic-role + lab-a2-diagnostic-profile

Press ENTER to continue or Ctrl+C to abort.
```

Wait for operator confirmation before proceeding.

### Section 1 — Delete Manual Resources First
Delete all manually created resources that are NOT in Terraform
state. Delete in reverse dependency order:
  1. IAM instance profile association (A2)
  2. Manual NACL rules (nacl-a, nacl-c-portal, nacl-c-dmz)
  3. Manual routes (lab-rt-b-untrust)
  4. Manual SG rule (C1)
  5. IAM role and profile

Each delete command must:
  - Print what it is deleting
  - Run the AWS CLI command
  - Print DONE or SKIPPED (if resource not found)
  - NOT stop on error (use try/catch)

### Section 2 — Terraform Destroy
Run terraform destroy in the dev environment:
```powershell
Set-Location C:\Users\Willi\projects\Labs\terraform-aws\environments\dev
terraform --% destroy -auto-approve
```

Capture output to:
  artifacts/results/teardown-<timestamp>.txt

### Section 3 — Post-Destroy Verification
After destroy completes, verify key resources are gone:
```powershell
# Check no running instances remain
aws ec2 describe-instances --filters "Name=tag:Project,Values=tgw-segmentation-lab" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text --region us-east-1

# Check no TGWs remain
aws ec2 describe-transit-gateways --filters "Name=tag:Project,Values=tgw-segmentation-lab" --query "TransitGateways[*].TransitGatewayId" --output text --region us-east-1

# Check no VPCs remain
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=tgw-segmentation-lab" --query "Vpcs[*].VpcId" --output text --region us-east-1
```

If any resources are still present, print a WARNING with the
resource IDs. Do not attempt to manually delete them — let the
operator investigate.

### Section 4 — Final Report
Print teardown summary:
  - Resources deleted manually: count
  - Terraform destroy result: success/failure
  - Remaining resources (if any): list
  - Time elapsed

---

## Step 5 — Save Updated Script

Save the updated script to:
  C:\Users\Willi\projects\Labs\teardown.ps1

Back up the original first:
  C:\Users\Willi\projects\Labs\teardown.ps1.bak

---

## Step 6 — Write Report

Write a report to:
  artifacts/results/2026-04-04_teardown-update.md

Include:
  - List of manual resources added to teardown
  - Changes made to the script structure
  - Any resources that could not be cleanly handled