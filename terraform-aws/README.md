# terraform-aws

Terraform AWS scaffold organized by reusable modules and per-environment root configurations.

## Why this layout

This follows Terraform guidance to:
- keep reusable code in `modules/`
- keep separate environment roots for separate state and variables
- use standard Terraform filenames (`main.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `providers.tf`, `backend.tf`)

## Structure

- `modules/`: reusable AWS building blocks
- `environments/dev`: development deployment root
- `environments/staging`: staging deployment root
- `environments/prod`: production deployment root
- `examples/simple-stack`: example of composing modules

## Typical workflow

1. Copy `terraform.tfvars.example` to `terraform.tfvars` in the target environment folder.
2. Copy `backend.hcl.example` to `backend.hcl` in the target environment folder.
3. Fill in backend values (S3 bucket, key, region, DynamoDB table).
4. Run Terraform from the environment folder.

Example:

```bash
cd environments/dev
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```
