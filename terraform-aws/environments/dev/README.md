# dev environment

Root Terraform configuration for development.

## Run

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Copy `backend.hcl.example` to `backend.hcl` and fill in your S3 bucket and DynamoDB table.
3. Run `terraform init -backend-config=backend.hcl`.
4. Run `terraform plan` and `terraform apply` in this folder.

## File layout used in this environment

- `main.tf`: module composition
- `variables.tf`: input declarations
- `locals.tf`: derived values and shared tags
- `outputs.tf`: exported values
