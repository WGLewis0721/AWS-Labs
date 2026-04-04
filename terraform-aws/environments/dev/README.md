# dev environment

This is the active TGW segmentation lab environment. It composes the `network`, `security`, and `compute` modules into the current working architecture described in the repo root README.

## What This Environment Represents

The `dev` environment is the real lab, not a toy example. It includes:

- VPC-A, VPC-B, VPC-C, and VPC-D
- TGW1 and TGW2
- per-subnet route tables and per-subnet NACLs
- the public management edge (`A1`, `A2`)
- the public customer-entry load balancer
- the private operator validation targets in VPC-B and VPC-C

This environment is the one that future troubleshooting and deployment prompts should assume by default.

## Backend

The active remote backend is:

- S3 bucket: `terraform-lab-wgl`
- DynamoDB table: `terraform-lab-db-wgl`
- region: `us-east-1`

Expected local files:

- `backend.hcl`
- `terraform.tfvars`

## Preferred Deployment Path

For a fresh or rebuilt lab, do not start with raw Terraform commands. Use the staged deploy script from the repository root:

```powershell
.\artifacts\scripts\deploy.ps1 -Environment dev
```

That script:

- seeds S3 bootstrap assets
- creates or reuses golden AMIs
- writes `generated.instance-amis.auto.tfvars.json`
- runs phased Terraform applies
- attaches SSM profiles
- bootstraps nginx through `A2`
- runs SSM netchecks

## Manual Terraform Path

Use direct Terraform commands only when you intentionally need raw module iteration or plan review.

```powershell
Set-Location .\terraform-aws\environments\dev
terraform --% init -backend-config=backend.hcl
terraform --% plan -out=tfplan -no-color
terraform --% apply tfplan
```

## Required Inputs

At minimum, populate:

- `public_key`
- `management_cidrs`
- `common_tags`

The deploy flow may also create:

- `generated.instance-amis.auto.tfvars.json`

That generated file is part of the current deployment workflow and should not be treated as a hand-maintained source file.

## Key Outputs

Important outputs:

- `a1_windows_public_ip`
- `a2_linux_public_ip`
- `alb_dns_name`
- `nat_gateway_eip`
- `private_ips`
- `instance_ids`
- `rdp_password_decrypt_command`
- `test_commands`
- `validation_targets`

Compatibility note:

- `alb_dns_name` remains the output name even though the underlying AWS resource is currently a TLS Network Load Balancer

## Current Validation Model

Primary operator validation targets:

- `https://10.1.3.10`
- `http://10.2.2.10`
- `https://10.2.2.10`
- `https://10.2.3.10`
- `https://10.2.4.10`

Negative control:

- `10.3.1.10` must fail from VPC-A

Do not rely on the removed internal NLB paths.
