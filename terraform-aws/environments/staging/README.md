# staging environment

This directory is a placeholder environment root. It is not the validated working lab.

## Current Status

- no current staging deployment workflow is maintained here
- the active and validated environment is `environments/dev`
- prompts and skills should not assume staging is wired the same way as `dev` unless the user explicitly asks to build it out

## If You Intend To Activate Staging

Before using this environment:

1. copy the `dev` operational expectations intentionally, not blindly
2. define a backend configuration for staging
3. create a real `terraform.tfvars`
4. decide whether staging should also use:
   - staged deploy script flow
   - golden AMI overrides
   - SSM netchecks
5. validate that the architecture matches the current direct private-IP model

Until those decisions are made, treat this directory as a scaffold only.
