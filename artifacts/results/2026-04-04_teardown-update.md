# Task: Teardown Script Update
Date: 2026-04-04
Performed by: Codex

## Summary

Updated the teardown workflow to match the current repo and live AWS environment without running any destructive commands.

## Changes Made

- Rewrote the teardown flow around a pre-flight inventory and operator pause.
- Added manual cleanup steps for legacy live fixes before Terraform destroy:
  - `lab-rt-b-untrust` legacy routes
  - `nacl-c-portal` legacy entries
  - `nacl-c-dmz` legacy entry `96`
  - `nacl-a` legacy entries
  - C1 security-group HTTP rule from `10.0.0.0/16`
- Added cleanup for later manual resources created outside Terraform:
  - `lab-a1-diagnostic-role` and `lab-a1-diagnostic-profile`
  - `lab-a2-diagnostic-role` and `lab-a2-diagnostic-profile`
  - `lab-netcheck-a1` and `lab-netcheck-a2` SSM documents
- Kept backend cleanup support with `-KeepBackend` preserved.
- Added post-destroy verification for:
  - running instances
  - TGWs
  - VPCs
  - diagnostic IAM roles
  - netcheck SSM documents

## Script Structure Updates

- Section 0: pre-flight inventory from `terraform state list` plus manual-resource summary
- Section 1: manual cleanup first, continuing on errors
- Section 2: Terraform destroy with output captured to `artifacts/results/teardown-<timestamp>.txt`
- Section 3: post-destroy verification and warnings for leftovers
- Section 4: final summary with counts and elapsed time

## Path Corrections

- The prompt referenced `C:\Users\Willi\projects\Labs\teardown.ps1`, but the repo's real teardown script lives at [teardown.ps1](C:/Users/Willi/projects/Labs/artifacts/scripts/teardown.ps1).
- The updated teardown workflow is now applied to the canonical script in [teardown.ps1](C:/Users/Willi/projects/Labs/artifacts/scripts/teardown.ps1).
- A backup of the prior teardown script was created at [teardown.ps1.bak](C:/Users/Willi/projects/Labs/teardown.ps1.bak) during the prompt-reconciliation step.
- The temporary root-level copy used during reconciliation was removed so there is only one active teardown script in the repo.

## Prompt Drift Noted

- `artifacts/COPILOT-CODIFY-FIXES-2026-04-04.md` was not present in the current repo.
- The prompt listed `nacl-c-dmz` rule `101` as a manual TCP/80 fix, but the live environment shows rule `101` is the long-lived TCP/22 rule. Only rule `96` is treated as the legacy manual TCP/80 fix in the rewritten teardown logic.

## Resources Not Handled as Destructive Actions in This Session

- No `terraform destroy` was run.
- No AWS delete commands were run.
- This was a script-and-report update only.
