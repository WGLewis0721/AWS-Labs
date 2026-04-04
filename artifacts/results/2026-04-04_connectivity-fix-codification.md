## Connectivity Fix Codification Report

Date: April 4, 2026

### Scope

Codify the live console-side connectivity fixes into Terraform and update the active operator documentation so future deployments converge to the current working lab state.

### Steps Taken

1. Reviewed:
   - `artifacts/results/connectivity-fix-report.md`
   - `artifacts/prompts/codex-connectivity-fix.md`
   - `artifacts/prompts/copilot-instructions-v1.md`
   - `artifacts/prompts/Seasoning.md`
   - `artifacts/skills/terraform-skill.md`
2. Updated Terraform in:
   - `terraform-aws/modules/network/main.tf`
   - `terraform-aws/modules/security/main.tf`
   - `terraform-aws/modules/compute/main.tf`
   - `terraform-aws/environments/dev/outputs.tf`
3. Updated active docs in:
   - `terraform-aws/README.md`
   - `terraform-aws/environments/dev/README.md`
   - `terraform-aws/modules/network/README.md`
   - `terraform-aws/modules/security/README.md`
   - `terraform-aws/modules/compute/README.md`
4. Updated operational scripts:
   - `artifacts/scripts/deploy.ps1`
   - `artifacts/scripts/teardown.ps1`
5. Ran:
   - `terraform fmt -recursive terraform-aws`
   - `terraform validate`
   - `terraform plan -no-color`
6. Imported the live console-managed route and NACL resources that already existed in AWS but were not yet present in Terraform state.
7. Re-ran `terraform plan -no-color` after imports to isolate remaining drift.

### Fixes Applied

#### Network

- Added VPC-C route table paths to `10.3.0.0/16` through `TGW2` for:
  - `c_dmz`
  - `c_portal`
  - `c_gateway`
  - `c_controller`
- Added the east-west NACL rules described in the connectivity fix prompt for:
  - `b_mgmt`
  - `b_trust`
  - `c_dmz`
  - `c_portal`
  - `d`

#### Security

- Added security group rules so the working east-west paths are represented in code:
  - `C1 -> B1 mgmt` on `22` and `443`
  - `C1 -> D1` on `443`
  - `D1 -> C1` on `443`
- Added the required ephemeral return-path rules for the relevant groups.

#### Compute

- Set `source_dest_check = false` for `c1_portal` and `d1` in Terraform to match the live working state.
- Extended the validation output so the east-west checks appear in `terraform output test_commands`.

#### Documentation and Scripts

- Updated the readmes to describe the current validated connectivity model.
- Updated `deploy.ps1` to print the east-west connectivity matrix in the final summary.
- Removed obsolete manual cleanup guidance from `teardown.ps1` that referred to superseded console-side cleanup steps.

### State Reconciliation

The following live resources were imported into Terraform state because they already existed in AWS:

- Route entries for:
  - `b_untrust-to-a`
  - `b_untrust-to-c`
  - `b_untrust-to-d`
  - `c_dmz-to-d`
  - `c_portal-to-d`
  - `c_gateway-to-d`
  - `c_controller-to-d`
- NACL rules for:
  - `b_mgmt`
  - `b_trust`
  - `c_dmz`
  - `c_portal`
  - `d`

After those imports, the route and NACL drift from the console fix was eliminated from plan output.

### Verification

- `terraform fmt -recursive terraform-aws`: passed
- `terraform validate`: passed
- `terraform plan -no-color`: reduced to one remaining replacement outside the connectivity fix scope
- AWS CLI verification confirmed the live working setting:
  - `lab-c1-portal` source/dest check is `False`
  - `lab-d1-customer` source/dest check is `False`

### Problems Encountered

1. Several route and NACL resources already existed in AWS from the manual console fix, so Terraform initially planned to create duplicates. This was corrected by importing the live resources into state.
2. A temporary Terraform state-lock conflict occurred when multiple Terraform backend reads were attempted in parallel. Subsequent Terraform work was run serially.
3. One unrelated Terraform drift remains:
   - `module.compute.aws_instance.this["c1_portal"]` still plans a replacement because the instance `user_data` hash in state does not match the current Terraform configuration.
   - The current plan shows the replacement is driven by `user_data`, not by the new route, NACL, security group, or source/dest-check changes.
   - Live AWS inspection shows `C1` and `D1` already have `SourceDestCheck = False`, so the connectivity fix itself is represented correctly.

### Recommended Next Steps

1. Do not run a blind `terraform apply` from the current plan until the `c1_portal` `user_data` replacement is intentionally addressed.
2. Decide whether the desired outcome is:
   - keep the current `C1` instance and suppress or separately resolve the bootstrap drift, or
   - intentionally replace `C1` in a controlled maintenance window so the instance matches the newer bootstrap config.
3. Once the `C1` bootstrap decision is made, run a fresh `terraform plan` and confirm the plan contains no unintended compute replacement before applying.

### Result

The Terraform code, active readmes, deploy script, and teardown script now reflect the April 4, 2026 working connectivity model. The console-side network and security fixes have been codified and reconciled into Terraform state. The only remaining Terraform action is a pre-existing `C1` bootstrap drift that should be handled separately from this connectivity fix.
