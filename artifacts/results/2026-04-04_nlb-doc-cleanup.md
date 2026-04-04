# NLB Terminology Cleanup

Date: 2026-04-04
Workspace: `C:\Users\Willi\projects\Labs`

## Steps Taken

1. Read the required session instructions:
   - `artifacts/prompts/copilot-instructions-v1.md`
   - `artifacts/prompts/Seasoning.md`
2. Reviewed the current local skill inventory under `artifacts/skills`.
3. Searched the repository for `NLB`, `nlb`, and `Network Load Balancer` references.
4. Updated the active operator docs, prompts, and skill guidance to remove the retired term from current-state documentation.
5. Verified that the active documentation set no longer contains `NLB` references.
6. Verified that the broader non-archive Markdown doc set no longer contains `NLB` references.

## Fixes Applied

- Rewrote current-state language to describe:
  - direct private-IP validation
  - absence of internal validation load balancers
  - `alb_dns_name` as a compatibility output name only
- Removed statements that described the current customer-entry load balancer using the retired term.
- Replaced stale references to old validation hostnames with generic `legacy internal DNS validation paths`.

Updated files:

- `terraform-aws/README.md`
- `terraform-aws/modules/network/README.md`
- `terraform-aws/environments/dev/README.md`
- `terraform-aws/modules/security/README.md`
- `artifacts/prompts/copilot-instructions-v1.md`
- `artifacts/prompts/Seasoning.md`
- `artifacts/skills/terraform-skill.md`
- `artifacts/skills/aws-cli-skill.md`
- `artifacts/skills/network-troubleshooting/SKILL.md`
- `artifacts/skills/network-troubleshooting/network-troubleshooting.md`

## Problems Encountered

- The repo still contains legacy `NLB` references in historical artifacts, archived prompts, raw outputs, and some script comments or status messages.
- Those were not changed in this pass because the request was limited to docs and current guidance rather than generated history or script internals.

## Recommended Next Steps

1. If you want zero `NLB` references anywhere in the repo, do a second pass on:
   - `artifacts/prompts/archives/`
   - `artifacts/results/`
   - `artifacts/scripts/`
2. If Amazon Q will index the whole repo, consider excluding:
   - `artifacts/results/`
   - `artifacts/prompts/archives/`
   - raw output files with historical pre-cleanup terminology
3. If desired, rename or replace any remaining script status messages so live validation output also avoids the retired term.
