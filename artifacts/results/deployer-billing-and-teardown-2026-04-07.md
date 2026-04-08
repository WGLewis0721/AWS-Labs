# Deployer Billing Access And Lab Teardown - 2026-04-07

## Result

- Deployer IAM user policy update: completed from the IAM policy side.
- Lab teardown: completed.
- Terraform destroy result: `Destroy complete! Resources: 300 destroyed.`
- Backend cleanup: completed manually after a teardown script bug.
- Golden AMI/snapshot cleanup: completed.
- Remaining core lab resources detected: none in final verification checks.

## IAM Billing And Cost Access

Caller verified:

- `arn:aws:iam::394281571385:user/Deployer`

The `Deployer` user already had these billing/cost related AWS managed policies:

- `arn:aws:iam::aws:policy/AWSPriceListServiceFullAccess`
- `arn:aws:iam::aws:policy/job-function/Billing`
- `arn:aws:iam::aws:policy/AWSBillingConductorFullAccess`
- `arn:aws:iam::aws:policy/CostOptimizationHubAdminAccess`

Added explicit read-only billing/cost viewer policies:

- `arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess`
- `arn:aws:iam::aws:policy/AWSBudgetsReadOnlyAccess`
- `arn:aws:iam::aws:policy/CostOptimizationHubReadOnlyAccess`

IAM simulation result:

- `ce:GetCostAndUsage`: `allowed`
- `aws-portal:ViewBilling`: `allowed`
- `budgets:ViewBudget`: `allowed`
- `cost-optimization-hub:ListRecommendations`: `allowed`

Cost Explorer API test:

- `aws ce get-cost-and-usage` still returned `AccessDeniedException: User not enabled for cost explorer access`.
- This is not a missing Deployer IAM policy in the simulation result. It appears to be an account-level Cost Explorer/IAM billing access gate that must be enabled outside this user-policy attachment step.

## Teardown Steps

Ran:

```powershell
.\artifacts\scripts\teardown.ps1 -Environment dev -Force
```

The script deleted the manual resources first:

- A1 IAM instance profile association
- A2 IAM instance profile association
- SSM document `lab-netcheck-a1`
- SSM document `lab-netcheck-a2`
- IAM role/profile bundle `lab-a1-diagnostic-role` / `lab-a1-diagnostic-profile`
- IAM role/profile bundle `lab-a2-diagnostic-role` / `lab-a2-diagnostic-profile`

Terraform destroy then removed the managed lab infrastructure:

- EC2 instances and ENIs
- VPCs, subnets, route tables, NACLs, security groups
- NAT gateway and EIPs
- TGWs, TGW attachments, TGW route tables, TGW routes, and TGW associations
- Customer-entry load balancer resources
- Flow log resources and ACM certificate

## Cleanup After Script Failure

The teardown script successfully destroyed Terraform resources and deleted the DynamoDB lock table, but failed during backend S3 bucket cleanup because the version listing did not include a `DeleteMarkers` property under strict mode.

Fix applied:

- Patched `artifacts/scripts/teardown.ps1` so `Remove-S3BucketCompletely` checks whether `Versions` and `DeleteMarkers` properties exist before reading them.

Manual backend cleanup completed:

- Deleted `92` object versions/delete markers from `s3://terraform-lab-wgl`.
- Deleted bucket `terraform-lab-wgl`.
- Verified `terraform-lab-db-wgl` is not found.

Golden AMI/snapshot cleanup completed:

- Deregistered `7` golden AMIs.
- Deleted the `7` associated snapshots.

## Final Verification

Verified zero remaining resources for:

- running/stopped/pending lab instances
- lab VPCs
- active lab TGWs
- lab NAT gateways
- lab EIPs
- lab ELBs
- lab flow-log log groups
- lab EBS volumes
- lab ENIs
- lab-tagged self-owned AMIs

Verified removed/not found:

- `terraform-lab-wgl` backend bucket: `404 Not Found`
- `terraform-lab-db-wgl` backend lock table: `ResourceNotFoundException`
- `lab-a1-diagnostic-role`
- `lab-a2-diagnostic-role`
- `lab-netcheck-a1`
- `lab-netcheck-a2`
- golden AMI snapshots: `InvalidSnapshot.NotFound`

## Problems Encountered

- Cost Explorer remained blocked by `User not enabled for cost explorer access` even after IAM simulation showed Deployer is allowed. Recommended next step is account-level Cost Explorer/IAM billing access enablement.
- `teardown.ps1` backend S3 cleanup failed on a missing `DeleteMarkers` property. Patched in repo and manually completed cleanup.

## Recommended Next Steps

- If Cost Explorer still does not open in the console, enable IAM user/role access to Billing and Cost Management or Cost Explorer access at the account level, then retry `aws ce get-cost-and-usage`.
- Because the Terraform backend bucket and DynamoDB lock table were deleted, recreate/bootstrap the backend before the next Terraform deploy if the deploy workflow does not recreate it automatically.

## Evidence Files

- `artifacts/results/deployer-attached-policies-final-20260407.json`
- `artifacts/results/deployer-billing-policy-simulation-20260407.json`
- `artifacts/results/deployer-cost-explorer-check-final-20260407.txt`
- `artifacts/results/teardown-20260407-171837.txt`
- `artifacts/results/teardown-backend-bucket-cleanup-20260407.json`
- `artifacts/results/teardown-golden-ami-snapshot-cleanup-20260407.json`
- `artifacts/results/teardown-resource-verification-summary-20260407.json`
- `artifacts/results/verify-amis-final-after-teardown-20260407.json`
- `artifacts/results/verify-golden-snapshots-final-summary-20260407.txt`
