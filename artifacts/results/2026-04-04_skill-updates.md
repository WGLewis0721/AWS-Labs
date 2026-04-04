# Task: Skill And Copilot Instruction Updates
Date: 2026-04-04
Session Reference: Post-session documentation capture for live troubleshooting on 2026-04-04
Performed by: Codex

## Files Updated

- `artifacts/skills/terraform-skill.md`
- `artifacts/skills/aws-cli-skill.md`
- `artifacts/skills/network-troubleshooting/SKILL.md`
- `artifacts/copilot-instructions-v1.md`

## Sections Added

### terraform-skill.md
Added:
- `## 2026-04-04 - NACL and Route Table Lessons from Live Troubleshooting`

Included:
- route table completeness rules
- NACL completeness rules
- VPC-A inbound NACL service-port lessons
- updated destroy-count safety interpretation
- nginx/user-data lessons for AL2023 instances

### aws-cli-skill.md
Added:
- `## 2026-04-04 - PowerShell AWS CLI Lessons`

Included:
- JSON output guidance for complex AWS CLI inspection
- PowerShell JMESPath boolean-filter warning
- A2 IAM instance profile details
- `trust.json` file-based assume-role policy guidance

### network-troubleshooting/SKILL.md
Added:
- `## Known Issues`
- `## 2026-04-04 - New Issues Found and Fixed`

Included:
- missing `lab-rt-b-untrust` return routes
- missing VPC-C default routes for internet egress
- `python3 http.server` blocking nginx
- missing HTTPS nginx configuration
- missing `nacl-a` inbound service-port rules
- SSH key permission issue on A2
- IMDSv2 script IP-detection issue
- `netcheck.sh` fail-fast behavior
- CRLF line-ending issue on transferred scripts

### copilot-instructions-v1.md
Added:
- `## Session 2026-04-04 - Operational Lessons`

Included:
- corrected local skill file paths
- PowerShell `terraform --%` guidance
- updated destroy-count threshold note
- `npx skills add --yes` guidance
- MCP availability note for Codex agent sessions

## Notes

- This was a documentation-only update session.
- No Terraform code was modified.
- No `terraform plan`, `terraform apply`, or `terraform destroy` commands were run.
