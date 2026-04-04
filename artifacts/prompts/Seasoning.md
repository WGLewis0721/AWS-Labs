Before taking any action, complete these steps in order:

## STEP 1 — Install established skills

npx skills add hashicorp/agent-skills/terraform/code-generation/skills/terraform-style-guide
npx skills add hashicorp/agent-skills/terraform/module-generation/skills/refactor-module
npx skills add terramate-io/agent-skills --skill terraform-best-practices
npx skills add awslabs/agent-plugins

## STEP 2 — Read local project skills

C:\Users\Willi\projects\Labs\artifacts\skills\terraform\SKILL.md
C:\Users\Willi\projects\Labs\artifacts\skills\aws-cli\SKILL.md

When conflicts exist between installed skills and local skills,
local skills take precedence — they encode project-specific
decisions that override general best practices.

## STEP 3 — Use MCP servers if configured in VS Code

- terraform (HashiCorp MCP) — query live Terraform Registry instead of web searching
- awslabs.terraform-mcp-server — AWS best practices and Checkov security scanning

## STEP 4 — Read and follow instructions

C:\Users\Willi\projects\Labs\artifacts\copilot-instructions-v1.md
C:\Users\Willi\projects\Labs\artifacts\OPERATOR-HANDOFF-APPLY.md

## EXECUTION RULES

- Run terraform init and terraform plan only
- Print the full plan destroy count before doing anything else
- STOP and report if destroy count exceeds 10 resources
- STOP and report if any TGW, VPC, or TGW attachment shows as destroy
- Do NOT run terraform apply without my explicit instruction
- Do NOT run any aws cli commands — I will run those myself

## AFTER I SAY APPLY

- Run terraform apply tfplan
- Capture all output to artifacts/results/apply-output-YYYY-MM-DD.txt
- Do NOT run validation commands — I will run those from the handoff

## AFTER I CONFIRM APPLY SUCCEEDED

Update local skill files with what was learned this session.
Append only — do not rewrite existing content.
Format: ## YYYY-MM-DD — [what changed and why]

Files to update:
  C:\Users\Willi\projects\Labs\artifacts\skills\terraform\SKILL.md
  C:\Users\Willi\projects\Labs\artifacts\skills\aws-cli\SKILL.md

Future task (do not start now): Convert local skills to Agent Skills
format by moving them to .skills/ at the repo root so they auto-load
in future Copilot sessions without explicit reference.