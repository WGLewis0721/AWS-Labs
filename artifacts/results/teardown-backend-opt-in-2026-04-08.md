# Teardown Backend Opt-In Update - 2026-04-08

## Steps Taken

1. Read `artifacts/prompts/copilot-instructions-v1.md`.
2. Read `artifacts/prompts/Seasoning.md`.
3. Reviewed the local Terraform and AWS CLI skills.
4. Updated `artifacts/scripts/teardown.ps1` so backend deletion is opt-in.
5. Updated repo docs/examples to match the new teardown behavior.
6. Ran PowerShell parse validation and `git diff --check`.

## Fixes Applied

- Added `-DeleteBackend` to `artifacts/scripts/teardown.ps1`.
- Changed teardown default behavior to preserve the Terraform backend bucket and DynamoDB lock table.
- Kept `-KeepBackend` as a deprecated compatibility flag so older commands still work.
- Added mutual-exclusion validation so `-DeleteBackend` and `-KeepBackend` cannot be used together.
- Updated preflight messaging in `teardown.ps1` to state whether backend preservation is default or explicitly disabled.
- Updated `terraform-aws/README.md` to document backend preservation by default and `-DeleteBackend` for explicit removal.
- Updated `artifacts/skills/aws-cli-skill.md` to reflect the same cleanup behavior.

## Problems Encountered

- No blocker encountered.
- I did not execute a live teardown again because the task was to change default script behavior, not destroy resources.

## Recommended Next Steps

- Use `.\artifacts\scripts\teardown.ps1 -Environment dev -Force` for normal lab cleanup.
- Use `.\artifacts\scripts\teardown.ps1 -Environment dev -DeleteBackend -Force` only when you intentionally want to remove backend state storage.
- At a later cleanup pass, remove `-KeepBackend` entirely if you no longer want the compatibility path.
