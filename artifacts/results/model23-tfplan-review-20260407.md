# Model 2+3 Phase 2 Terraform Plan Review

Date: 2026-04-07 14:23:52 -05:00

## Scope

Codify the already-validated Model 2+3 CLI spike into Terraform without running `terraform apply`.

## Steps Taken

1. Read the required baseline instructions:
   - `artifacts/prompts/copilot-instructions-v1.md`
   - `artifacts/prompts/Seasoning.md`
2. Reviewed local skills under `artifacts/skills`, including:
   - `artifacts/skills/terraform-skill.md`
   - `artifacts/skills/aws-cli-skill.md`
   - `artifacts/skills/network-troubleshooting/SKILL.md`
3. Read the Phase 2 prompt:
   - `artifacts/prompts/Redesign-v3/Phase2/COPILOT-MODEL23-PHASE2-TERRAFORM-GENERATED.md`
4. Read the spike report:
   - `artifacts/results/model23-cli-spike-20250714.md`
5. Reviewed the current network and security module implementations.
6. Verified live AWS TGW route tables, associations, routes, appliance mode, NACL entries, and SG rule IDs.
7. Ran a refresh-only plan and saved it to:
   - `artifacts/results/model23-refresh-only-20260407.txt`
8. Updated Terraform code and import/remove blocks.
9. Ran:
   - `terraform fmt -recursive`
   - `terraform validate`
   - `terraform plan -out=tfplan -no-color`
10. Saved the final plan output to:
   - `artifacts/results/model23-tfplan-20260407.txt`

## Fixes Applied

- Added the four Model 2+3 TGW route table resources:
  - `tgw1_spoke`
  - `tgw1_firewall`
  - `tgw2_spoke`
  - `tgw2_firewall`
- Added explicit Model 2+3 TGW route table association resources.
- Added explicit Model 2+3 TGW route resources.
- Added `appliance_mode_support` to the existing VPC-B TGW attachments.
- Removed the obsolete generic TGW route table association resource and added a root `removed` block with `destroy = false` so stale old association state is discarded without deleting anything.
- Added six missing NACL rules to the local NACL rule map:
  - `b_trust-ingress-92`
  - `b_trust-egress-101`
  - `c_dmz-ingress-99`
  - `c_portal-ingress-93`
  - `c_portal-ingress-94`
  - `c_portal-egress-89`
- Added the three VPC-C SG ingress rules inline in the existing SG resources:
  - `lab-sg-c1-portal` HTTPS from `10.1.2.0/24`
  - `lab-sg-c2-gateway` HTTPS from `10.1.2.0/24`
  - `lab-sg-c3-controller` HTTPS from `10.1.2.0/24`
- Added `terraform-aws/environments/dev/imports-model23.tf` with import blocks for the live TGW and NACL resources.
- Recreated `terraform-aws/environments/dev/generated.instance-amis.auto.tfvars.json` with current live AMI IDs to suppress unrelated latest-AMI replacement drift.

## Plan Summary

Final plan:

```text
Plan: 25 to import, 1 to add, 0 to change, 1 to destroy.
```

Expected/imported resources:

- 4 `aws_ec2_transit_gateway_route_table`
- 6 `aws_ec2_transit_gateway_route_table_association`
- 9 `aws_ec2_transit_gateway_route`
- 6 `aws_network_acl_rule`

Notes:

- `c_dmz-ingress-100` was listed in the prompt but was already represented in the existing Terraform state/config, so no new import block was added for that rule.
- SG rules were codified inline instead of as standalone `aws_security_group_rule` resources because the existing security module manages rules inline. Mixing inline and standalone SG rule resources would create unsafe rule-management drift.
- The old generic TGW association state entries will no longer be managed, but the plan explicitly says they will not be destroyed.

## Hard Stop Review

- `aws_vpc` destroy/replace: not present.
- `aws_ec2_transit_gateway` destroy/replace: not present.
- `aws_ec2_transit_gateway_vpc_attachment` destroy/replace: not present.
- Unexpected compute replacement: present.

Remaining unexpected replacement:

```text
module.compute.aws_instance.this["c1_portal"] must be replaced
user_data: 6d0b27c6186361838e5cd688b27303120bc15ae7 -> 593603c4ea6195ba4409aaa363b11539dafda50c
```

## Problems Encountered

- The prompt expected seven NACL rule imports, but one of them (`c_dmz-ingress-100`) was already codified.
- The prompt expected standalone SG rule imports, but the current module uses inline SG rules, so inline codification was safer.
- Terraform `removed` blocks cannot target individual `for_each` instances; this required removing the obsolete generic association resource block and targeting the whole old association resource with `destroy = false`.
- The first plan included six unrelated EC2 replacements due latest-AMI drift. This was reduced by restoring the generated AMI override file with current live AMIs.
- One unrelated hard-stop replacement remains: `c1_portal` user data drift.

## Recommended Steps

1. Do not run `terraform apply tfplan` while the `c1_portal` replacement remains in the plan.
2. Decide separately whether to keep the existing `C1` instance or intentionally replace it for the user-data/bootstrap drift.
3. After the `C1` decision, rerun `terraform plan -out=tfplan -no-color` and confirm the plan has no unexpected compute replacement.
4. If `C1` must be preserved, resolve or suppress the user-data drift in a separate, explicit maintenance task before applying the Model 2+3 imports.

## Final Verdict

STOP.

The Phase 2 Terraform codification and import blocks are in place and validated, but the final plan is not ready for operator apply because it still includes an unexpected `c1_portal` replacement outside the Model 2+3 change list.
