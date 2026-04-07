# Amazon Q Fresh Build Playbook Save - 2026-04-07

## Steps Taken

1. Read `artifacts/prompts/copilot-instructions-v1.md`.
2. Read `artifacts/prompts/Seasoning.md`.
3. Reviewed the local skills under `artifacts/skills`.
4. Created a markdown review file for the Amazon Q console-build guidance.
5. Added a short review note at the top of the saved file to mark it as captured guidance, not the authoritative repo architecture.

## File Created

- `artifacts/prompts/Redesign-v3/amazon-q-fresh-build-console-playbook-2026-04-07.md`

## Fixes Applied

- Lightly formatted the pasted Amazon Q content into headings, tables, code blocks, and checklists.
- Converted arrow symbols and chat-copy artifacts into plain markdown for easier review.
- Added review flags for items that should be reconciled against the current Terraform/deploy workflow before use.

## Problems Encountered

- No blocker encountered.
- The source guidance includes some items that may be stale or need verification against the current repo, including manual console deployment, C-host SSH expectations, and a reference to a previous TGW routing playbook.

## Recommended Next Steps

- Review the saved playbook against the current Terraform and `deploy.ps1` workflow before treating it as implementation guidance.
- If the playbook is still useful, consider moving the verified parts into the canonical deployment docs and leaving this file as source reference.
