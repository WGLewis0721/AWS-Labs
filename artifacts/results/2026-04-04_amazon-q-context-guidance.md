# Amazon Q Context Guidance

Date: 2026-04-04
Workspace: `C:\Users\Willi\projects\Labs`

## Steps Taken

1. Re-read required local instructions:
   - `artifacts/prompts/copilot-instructions-v1.md`
   - `artifacts/prompts/Seasoning.md`
2. Reviewed available local skill directories under `artifacts/skills`.
3. Verified current Amazon Q Developer context features from AWS documentation:
   - explicit chat context
   - workspace indexing
   - pinned context
   - project rules
   - memory bank
4. Checked the repo for existing Amazon Q project rules.

## Fixes Applied

- No repo changes were required for this answer.
- Verified that there is currently no `.amazonq` folder in the project, so no automatic Q rules are active yet.

## Problems Encountered

- None blocking.
- The main gap is configuration: the repo has strong documentation, but Amazon Q-specific automatic context files have not been added yet.

## Recommended Next Steps

1. Enable `@workspace` indexing in Amazon Q for this repo.
2. Create `project-root/.amazonq/rules` and add Markdown rules for:
   - architecture
   - deployment workflow
   - validation targets
   - guardrails / do-not-do rules
3. Generate an Amazon Q memory bank from the repo after the rules are in place.
4. Save a few reusable prompts for common lab tasks.
5. For live environment insight, feed Q current artifacts such as:
   - `terraform output -json`
   - latest SSM netcheck results
   - recent deploy reports under `artifacts/results`

## Sources Used

- https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/ide-chat-context.html
- https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/workspace-context.html
- https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/context-pinning.html
- https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/context-project-rules.html
- https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/context-memory-bank.html
