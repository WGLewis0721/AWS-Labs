# terraform-aws

Terraform AWS scaffold organized by reusable modules and per-environment root configurations.

## Why this layout

This follows Terraform guidance to:
- keep reusable code in `modules/`
- keep separate environment roots for separate state and variables
- use standard Terraform filenames (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `backend.tf`)

## Structure

- `modules/`: reusable AWS building blocks
- `environments/dev`: development deployment root
- `environments/staging`: staging deployment root
- `environments/prod`: production deployment root
- `examples/simple-stack`: example of composing modules

## Typical workflow

1. Copy `terraform.tfvars.example` to `terraform.tfvars` in the target environment folder.
2. Update backend settings in `backend.tf`.
3. Run Terraform from the environment folder.

Example:

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```
