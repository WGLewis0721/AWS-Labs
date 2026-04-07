# Model 2+3 Phase 3 Docs And Scripts Update - 2026-04-07

## Summary

Updated the lab documentation, local skills, and validation/deployment scripts to reflect the applied Model 2+3 architecture.

Current architecture captured by these updates:

- Model 2+3 two-table TGW routing is active and Terraform-managed.
- Each TGW uses Spoke and Firewall route tables for inspected traffic.
- VPC-B TGW attachments require appliance mode.
- Destination NACLs and SGs must account for transit source traffic from `10.1.2.0/24`.
- B1 OS-level tcpdump is not valid proof of TGW transit visibility because TGW uses AWS-managed attachment ENIs.

## Files Updated

- `artifacts/skills/terraform-skill.md`
  - Added the Terraform-applied Model 2+3 steady state, Spoke/Firewall route table pattern, firewall-default-route nuance, VPC-D egress path, import/order notes, and tcpdump visibility warning.

- `artifacts/skills/aws-cli-skill.md`
  - Added Model 2+3 AWS CLI validation commands for route tables, associations, routes, appliance mode, and required diagnostic IAM permissions.

- `artifacts/skills/network-troubleshooting/SKILL.md`
  - Added a two-table TGW verifier and the association-swap known issue.
  - Kept the newer lesson that B1 tcpdump is not a valid TGW transit proof.

- `artifacts/skills/network-troubleshooting/network-troubleshooting.md`
  - Updated the canonical troubleshooting workflow with Model 2+3 expectations, NACL/SG transit rules, two-table verification, and tcpdump/Reachability Analyzer limitations.

- `artifacts/prompts/copilot-instructions-v1.md`
  - Added current Model 2+3 architecture defaults, deployment verification expectations, NACL/SG transit requirements, and the tcpdump caveat.

- `artifacts/prompts/Seasoning.md`
  - Added Model 2+3 current-architecture defaults and the tcpdump caveat.

- `terraform-aws/README.md`
  - Updated the current architecture, topology, deployment phases, validation notes, and lessons learned for the applied two-table TGW pattern.

- `artifacts/scripts/README.md`
  - Documented that deploy/netcheck scripts now verify Model 2+3 route tables, appliance mode, and transit-source controls.

- `artifacts/scripts/netcheck.sh`
  - Replaced the stale single-TGW-route-table check with Spoke/Firewall route table checks.
  - Added VPC-B appliance-mode checks.
  - Added Model 2+3 NACL checks for `b-trust`, `c-dmz`, and `c-portal`.
  - Added a 10-request C1 HTTPS stability check.
  - Updated the local A2 copy at `/home/ec2-user/netcheck.sh`.
  - Uploaded the updated SSM payload to `s3://terraform-lab-wgl/ssm/netcheck/a2/netcheck.sh`.

- `artifacts/scripts/local-netcheck.ps1`
  - Updated the operator-laptop validation to use Spoke/Firewall route tables.
  - Added VPC-B appliance-mode checks.
  - Expanded NACL checks for Model 2+3 transit rules.
  - Expanded SG checks for C1/C2/C3 HTTPS ingress from `10.1.2.0/24`.

- `artifacts/scripts/deploy.ps1`
  - Added `PHASE 6B - Two-Table TGW Pattern Verification` after full Terraform convergence and before bootstrap/netchecks.
  - The phase verifies Spoke/Firewall RTs, Spoke RT default routes to VPC-B, Firewall RT association/routes, and VPC-B attachment appliance mode.

- `artifacts/scripts/teardown.ps1`
  - Did not add manual TGW deletion from the prompt because that instruction is now stale.
  - Added a safe pre-destroy note/check confirming Model 2+3 TGW resources are Terraform-managed and should be removed by Terraform destroy.

## Out-Of-Date Prompt Items Corrected

- Did not add the prompt's tcpdump verifier as written.
  - Reason: the CLI spike found B1 tcpdump can show zero packets while the inspected path is working because transit uses AWS-managed TGW attachment ENIs.

- Did not add manual teardown deletion for Model 2+3 TGW routes/route tables.
  - Reason: after the 2026-04-07 apply, those resources are in Terraform state; manual pre-destroy deletion would fight Terraform.

- Did not treat Reachability Analyzer false negatives on multi-hop inspected paths as authoritative.
  - Reason: RA does not model TGW source-IP substitution to `10.1.2.0/24`.

## Verification

- `artifacts/scripts/netcheck.sh` parsed with Git Bash: passed.
- `artifacts/scripts/local-netcheck.ps1` parsed as a PowerShell scriptblock with UTF-8 input: passed.
- `artifacts/scripts/deploy.ps1` parsed as a PowerShell scriptblock with UTF-8 input: passed.
- `artifacts/scripts/teardown.ps1` parsed as a PowerShell scriptblock with UTF-8 input: passed.
- `git diff --check`: passed, with a line-ending warning for `artifacts/scripts/local-netcheck.ps1`.
- S3 payload verification:
  - key: `ssm/netcheck/a2/netcheck.sh`
  - size: `20802`
  - ETag: `16bdd76600a0871de6bbcefe062da117`
  - LastModified: `2026-04-07T20:29:14+00:00`
- A2 live copy verification:
  - host: `44.204.129.98`
  - path: `/home/ec2-user/netcheck.sh`
  - confirmed `SECTION 7 - Model 2+3 Path Stability` exists.

## Problems Encountered

- WSL `bash` on this host fails with `/bin/bash` missing, so Git Bash was used for the shell syntax check.
- The first PowerShell parse attempt without explicit UTF-8 input misread existing non-ASCII dash characters; rerunning with `-Encoding UTF8` passed.
- `git diff --check` reports that `artifacts/scripts/local-netcheck.ps1` will be normalized from CRLF to LF when Git next touches it. This is a line-ending warning, not a syntax failure.

## Recommended Next Steps

- Run `lab-netcheck-a2` through SSM or execute `KEY_PATH=~/tgw-lab-key.pem bash ~/netcheck.sh` on A2 to collect a fresh Model 2+3 validation report.
- If `local-netcheck.ps1` line endings matter for Windows editors, normalize that file intentionally before committing.
- Keep the Phase 2 Terraform changes and these Phase 3 documentation/script updates in the same review context so the docs match the applied state.
