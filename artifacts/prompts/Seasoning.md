Before taking action, use this baseline setup. It is intentionally generic so it can be paired with task-specific prompts.

## STEP 1 - Install baseline external skills only if needed

Use `--yes` so sessions stay non-interactive:

```bash
npx skills add --yes hashicorp/agent-skills/terraform/code-generation/skills/terraform-style-guide
npx skills add --yes hashicorp/agent-skills/terraform/module-generation/skills/refactor-module
npx skills add --yes terramate-io/agent-skills --skill terraform-best-practices
npx skills add --yes awslabs/agent-plugins
```

Do not reinstall these blindly if the task does not depend on them.

## STEP 2 - Read the local project skills that match the task

Current local skill paths:

- `C:\Users\Willi\projects\Labs\artifacts\skills\terraform-skill.md`
- `C:\Users\Willi\projects\Labs\artifacts\skills\aws-cli-skill.md`
- `C:\Users\Willi\projects\Labs\artifacts\skills\network-troubleshooting\SKILL.md`

Local skills take precedence over external skills because they capture the lab-specific architecture and known-good workflows.

## STEP 3 - Read the current session instructions

Always read:

- `C:\Users\Willi\projects\Labs\artifacts\prompts\copilot-instructions-v1.md`

Then read the task-specific prompt if one exists.

## STEP 4 - Default execution strategy

Use the smallest workflow that solves the task:

- docs task -> edit docs only
- diagnosis task -> use read-only CLI checks and the netcheck scripts
- deployment task -> prefer `artifacts\scripts\deploy.ps1`
- teardown task -> prefer `artifacts\scripts\teardown.ps1`
- routine validation task -> prefer the SSM netcheck documents before long manual sessions

## CURRENT ARCHITECTURE DEFAULTS

Assume these are true unless the task explicitly says they changed:

- no internal `NLB-B` or `NLB-C`
- direct private-IP validation from `A1` and `A2`
- one public customer-entry load balancer only
- Route 53 is not used for custom lab resources
- current direct validation targets are:
  - `10.1.3.10`
  - `10.2.2.10`
  - `10.2.3.10`
  - `10.2.4.10`
- `10.3.1.10` must fail from VPC-A

## EXECUTION RULES

- verify whether a task or manual fix is already complete before redoing it
- prefer existing repo scripts over handwritten one-off command sequences
- use `terraform --%` in PowerShell
- prefer `aws ... --output json` for anything complex in PowerShell
- use SSM docs and script payloads already staged in the repo and S3
- keep context usage tight: read only the files needed for the active task

## KNOWN CANONICAL SCRIPTS

- deploy: `C:\Users\Willi\projects\Labs\artifacts\scripts\deploy.ps1`
- teardown: `C:\Users\Willi\projects\Labs\artifacts\scripts\teardown.ps1`
- A2 netcheck: `C:\Users\Willi\projects\Labs\artifacts\scripts\netcheck.sh`
- A1 netcheck: `C:\Users\Willi\projects\Labs\artifacts\scripts\netcheck-a1.ps1`
- SSM docs:
  - `lab-netcheck-a1`
  - `lab-netcheck-a2`

## MCP NOTE

If MCP servers are unavailable in the Codex environment, do not block on them. Proceed with the local skills, repo scripts, AWS CLI, and web verification when needed.
