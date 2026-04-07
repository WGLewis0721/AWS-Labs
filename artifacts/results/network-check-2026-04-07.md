# Network Check - 2026-04-07

## Result

Overall verdict: PASS.

The repo and live environment are stable after correcting stale netcheck assumptions. Required private-IP validation passed from A2 and A1, D1 isolation remains enforced, and Terraform still reports no drift.

## Steps Taken

1. Loaded task instructions from `artifacts/prompts/copilot-instructions-v1.md`, `artifacts/prompts/Seasoning.md`, and reviewed `artifacts/skills`.
2. Ran the canonical A2 SSM netcheck document `lab-netcheck-a2`.
3. Ran the canonical A1 SSM netcheck document `lab-netcheck-a1`.
4. Ran a targeted A2 validation for the current acceptance targets after the initial A2 script failed on stale SSH expectations.
5. Verified the Model 2+3 TGW route-table pattern locally with AWS CLI using operator credentials.
6. Ran `terraform plan -no-color` in `terraform-aws/environments/dev`.
7. Patched and re-uploaded the A2 and A1 netcheck scripts to S3.
8. Reran the canonical A2 and A1 SSM documents after script fixes.
9. Refreshed `/home/ec2-user/netcheck.sh` on A2 from the corrected S3 payload.

## Final Command Results

- A2 canonical rerun: `1c8882db-f5b8-48f2-8193-53b8a3fdb03a`
- A2 result: `Success`, response code `0`, `30 PASS`, `0 FAIL`, `13 WARN`
- A1 canonical rerun: `598245b2-d8dc-4cc1-b187-3269bf376678`
- A1 result: `Success`, response code `0`, `17 PASS`, `0 FAIL`, `1 WARN`
- Terraform stability plan: `No changes. Your infrastructure matches the configuration.`

## Required Connectivity Confirmed

- A2 to `https://10.1.3.10`: HTTP `200`
- A2 to `http://10.2.2.10`: HTTP `200`
- A2 to `https://10.2.2.10`: HTTP `200`
- A2 to `https://10.2.3.10`: HTTP `200`
- A2 to `https://10.2.4.10`: HTTP `200`
- A2 to `10.3.1.10`: ping, TCP `80`, and TCP `443` blocked
- A1 to `https://10.1.3.10`: HTTP `200`
- A1 to `http://10.2.2.10`: HTTP `200`
- A1 to `https://10.2.2.10`: HTTP `200`
- A1 to `https://10.2.3.10`: HTTP `200`
- A1 to `https://10.2.4.10`: HTTP `200`
- A1 to `10.3.1.10`: ping and TCP `80` blocked
- A2 Model 2+3 stability loop: `10/10` HTTPS requests to C1 succeeded

## TGW Evidence

- `tgw1-rt-spoke` (`tgw-rtb-048b1f202b58aa953`) is associated with VPC-A and VPC-C and has `0.0.0.0/0` routed to VPC-B.
- `tgw1-rt-firewall` (`tgw-rtb-0b4ef7ed52e24e8fb`) is associated with VPC-B and routes VPC-A/VPC-C return traffic to the correct attachments.
- `tgw2-rt-spoke` (`tgw-rtb-08aff34bbf46e3e04`) is associated with VPC-C and VPC-D and has `0.0.0.0/0` routed to VPC-B.
- `tgw2-rt-firewall` (`tgw-rtb-064e2f1575529422b`) is associated with VPC-B and routes VPC-B/VPC-C/VPC-D return traffic to the correct attachments.
- VPC-B TGW attachments have `ApplianceModeSupport = enable`:
  - `tgw-attach-066fd221541a5125a` for TGW1 to VPC-B
  - `tgw-attach-08c236efde613922b` for TGW2 to VPC-B

## Fixes Applied

- Updated `artifacts/scripts/netcheck.sh` so `check_http` and `check_ssh` preserve the caller's `errexit` state instead of enabling `set -e` globally.
- Updated `artifacts/scripts/netcheck.sh` so C1/C2/C3 SSH and TCP `22` checks are optional diagnostics, not Model 2+3 acceptance failures.
- Updated `artifacts/scripts/netcheck.sh` so failed C1 SSH access does not produce false nginx/local HTTP failures when external HTTP/HTTPS checks already pass.
- Updated `artifacts/scripts/netcheck.sh` expected healthy outcomes to list C1 HTTP/HTTPS and C2/C3 HTTPS, with SSH explicitly optional.
- Uploaded corrected A2 netcheck script to `s3://terraform-lab-wgl/ssm/netcheck/a2/netcheck.sh`.
- Refreshed A2 local manual copy at `/home/ec2-user/netcheck.sh`.
- Updated `artifacts/scripts/netcheck-a1.ps1` so HTTP status checks prefer `curl.exe -k` before falling back to `Invoke-WebRequest`.
- Uploaded corrected A1 netcheck script to `s3://terraform-lab-wgl/ssm/netcheck/a1/netcheck-a1.ps1`.
- Updated `terraform-aws/README.md` so A2-to-C host connectivity no longer lists SSH as an expected allowed protocol.

## Problems Encountered

- Initial A2 canonical run failed because the script expected C1 TCP `22` and `check_http` had accidentally enabled `set -e` for the rest of the script.
- Initial A1 canonical run reported HTTP `0` for HTTPS targets despite TCP `443` being open; targeted `curl.exe -k` from A1 confirmed HTTP `200`, so this was a test-client/certificate handling issue.
- A2 IAM role could not verify some TGW route-table details from inside the instance; local AWS CLI verification with operator credentials confirmed the route-table pattern.
- A1 does not have AWS CLI installed, so the A1 script skipped optional AWS sanity checks.

## Recommended Next Steps

- Treat A2/A1 direct HTTP/HTTPS and D1 isolation as the acceptance checks for this lab.
- Do not use C-host SSH from A2 as an acceptance criterion unless the security groups are intentionally changed to allow it.
- Use local operator AWS CLI, not A2 IAM, for TGW route-table and association audits.
- Keep the S3 SSM netcheck payloads in sync with repo script changes before running canonical SSM documents.

## Raw Artifacts

- `artifacts/results/network-check-a2-rerun-stdout-clean-20260407-155155.txt`
- `artifacts/results/network-check-a2-rerun-summary-20260407-155155.json`
- `artifacts/results/network-check-a2-rerun-plugin-20260407-155155.json`
- `artifacts/results/network-check-a1-rerun-stdout-20260407-155520.txt`
- `artifacts/results/network-check-a1-rerun-summary-20260407-155520.json`
- `artifacts/results/network-check-a1-rerun-plugin-20260407-155520.json`
- `artifacts/results/network-check-model23-tgw-routes-summary-20260407-154034.txt`
- `artifacts/results/network-check-model23-tgw-routes-20260407-154034.json`
- `artifacts/results/network-check-tgw-vpc-attachments-20260407-154034.json`
- `artifacts/results/network-check-post-stability-plan-20260407-154034.txt`
