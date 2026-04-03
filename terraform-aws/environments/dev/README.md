# dev environment

Terraform root for the TGW segmentation lab. This environment composes the reusable
`network`, `security`, and `compute` modules into the lab topology described in
`artifacts/copilot-instructions-v1.md`.

## Backend

This environment expects an S3 backend and DynamoDB lock table with these names:

- S3 bucket: `terraform-lab-wgl`
- DynamoDB table: `terraform-lab-db-wgl`

The backend resources must exist before running a normal `terraform init`.

## Inputs

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Replace the placeholder `public_key` with the public key that matches `tgw-lab-key.pem`.
3. Narrow `management_cidrs` if you want tighter access than `0.0.0.0/0`.

## Workflow

1. For syntax-only validation without the remote backend, run `terraform init -backend=false -reconfigure`.
2. For real state operations, run `terraform init -backend-config=backend.hcl`.
3. Run `terraform plan`.
4. Run `terraform apply`.

## Outputs

The root outputs provide:

- public IPs for A1 and A2
- private IPs for B1, C1, and D1
- a ready-to-use `rdp_password_decrypt_command`
- a ready-to-use `test_commands` matrix for post-apply validation
