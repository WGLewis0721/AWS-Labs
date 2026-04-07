# Amazon Q Developer — Model 2+3 Architecture Build
# Combined Centralized Egress + East-West Inspection
# Run this in: q chat (Amazon Q Developer CLI agent mode)
# Working directory: C:\Users\Willi\projects\Labs

You are an AWS infrastructure engineer executing a planned
architecture change on a live TGW segmentation lab in
us-east-1. You have full AWS CLI access and will execute
commands directly in the terminal.

---

## YOUR ROLE

You are NOT just generating commands for the operator to run.
You ARE running the commands yourself, reading the output,
adapting if something fails, and verifying each step before
moving to the next.

Confirm with the operator before any step that modifies
existing associations or deletes resources.
Do NOT confirm for read-only describe commands — run those
immediately.

---

## READ THESE FILES FIRST

Before doing anything else, read all three phase prompts:

  artifacts\COPILOT-MODEL23-PHASE1-PART1.md
  artifacts\COPILOT-MODEL23-PHASE1-PART2.md
  artifacts\COPILOT-MODEL23-PHASE1-PART3.md

Also read:
  artifacts\skills\terraform-skill.md
  artifacts\skills\aws-cli-skill.md
  artifacts\skills\network-troubleshooting\SKILL.md

After reading, summarize in 5 bullet points:
  - What architecture we are building
  - What the two TGW route tables do
  - Why appliance mode matters
  - The three traffic flows to test
  - What the final report must contain

Do not proceed until the operator confirms the summary is correct.

---

## EXECUTION APPROACH

Work through the three parts sequentially. Within each part,
follow this loop for every command:

  1. State what you are about to do and why
  2. Run the command
  3. Read the output
  4. Confirm success or diagnose failure
  5. Record the result in the running log
  6. Move to the next step

Do not batch multiple commands together unless they are
genuinely independent (like parallel describe calls).
For any create/modify/delete — one at a time with verification.

---

## PART 1 EXECUTION

### Pre-flight

Check AWS credentials and region before anything else:
  aws sts get-caller-identity --region us-east-1
  aws configure get region

If region is not us-east-1, set it:
  aws configure set default.region us-east-1

### IAM Permission

Add the missing TGW search permission to the A2 diagnostic role.
Read the exact policy from Part 1 and execute it.
Verify with get-role-policy before proceeding.

### Baseline Snapshot

Run all three describe commands from Part 1 and save outputs
to artifacts\results\ with today's date in the filename.
Confirm file sizes are non-zero before proceeding.

### Collect All Resource IDs

Run every variable-collection command from Part 1.
Print each ID as it is collected.

Validate: if any ID is empty, "None", or contains "XXXX",
STOP and diagnose. The tag filter is wrong or the resource
does not exist.

After collecting all IDs, write them to a file:
  artifacts\results\model23-resource-ids-YYYYMMDD.txt

This file is the handoff between parts. If this session ends
and a new session starts, this file provides continuity.

### Create Spoke Route Tables

Run the create commands from Part 1.
After each create, immediately describe to confirm State=available.

### Tag Firewall Route Tables

Run the tagging commands. Verify tags applied correctly.

### Enable Appliance Mode

Run both modify commands.
Verify with describe after each.
If either returns "disable" after the modify, diagnose
and retry before proceeding. This is a hard gate.

### Part 1 Connectivity Check

Run the baseline connectivity check from A2.
You cannot SSH into A2 directly — print the commands for the
operator to run manually, wait for them to paste the results,
then record the results and confirm baseline still holds.

Print clearly:
  === OPERATOR ACTION REQUIRED ===
  SSH to A2 and run these commands, then paste the output here:
  [commands]
  ================================

After operator pastes results, record them and confirm all pass.

Write the Part 1 completion report to:
  artifacts\results\model23-part1-YYYYMMDD.md

Ask operator: "Part 1 complete. Ready to proceed to Part 2? (yes/no)"
Do NOT proceed until operator says yes.

---

## PART 2 EXECUTION

### Load IDs

Read artifacts\results\model23-resource-ids-YYYYMMDD.txt
and set all variables. Print each one to confirm loaded.

### Pre-Step Warning

Before moving any association, warn the operator:

  === WARNING ===
  Association moves will cause 30-60 second connectivity gaps.
  This is expected and normal.
  Proceeding with VPC-A association move.
  Press ENTER to continue or type STOP to abort.
  ===============

Wait for operator input before each association move.

### Move Associations

For each association move (VPC-A, VPC-C, VPC-D):
  1. Warn operator
  2. Run disassociate
  3. Wait 30 seconds (use Start-Sleep or sleep)
  4. Run associate
  5. Wait 15 seconds
  6. Verify with get-transit-gateway-route-table-associations
  7. Confirm correct RT shown before moving to next

### Add Routes

Run all route creation commands from Part 2.
For each RouteAlreadyExists error: log as "already present"
and continue — this is not a failure.

### Update VPC-B Route Table

First describe the existing routes.
Then add any missing ones.
Print the final route table for operator to review.

### Part 2 Sanity Check

Print the manual test commands for A2 again.
Wait for operator to paste results.
If C1 returns 000: STOP. Do not proceed to Part 3.
Diagnose using traceroute output.

Write Part 2 completion report to:
  artifacts\results\model23-part2-YYYYMMDD.md

Ask operator: "Part 2 complete. Ready to proceed to Part 3? (yes/no)"

---

## PART 3 EXECUTION

### Run All 7 Tests

For each test in Part 3:
  - Print the test name and what it proves
  - Print the commands for the operator to run on A2/B1/D1
  - Wait for operator to paste results
  - Record pass/fail with the actual output
  - If FAIL: diagnose immediately before moving to next test

The tcpdump tests (Tests 1b, 2b, 3b) require two SSH sessions
simultaneously. Give the operator clear instructions:
  "Open two terminals. In Terminal 1, SSH to B1 and run
  [tcpdump command]. In Terminal 2, SSH to A2 and run
  [curl command]. Paste both outputs here."

### Route Verification from A2

After Part 1 IAM fix, A2 can run AWS CLI commands.
Give the operator the exact commands to run on A2 to verify
the Spoke RT and Firewall RT routes. These can be piped
directly in the terminal since A2 has the diagnostic role.

### Run netcheck.sh

Instruct operator to run netcheck.sh on A2 and paste output.
Compare against the baseline from the start of Part 1.
Any regressions must be explained.

---

## GENERATE TWO FINAL OUTPUTS

### Output 1 — CLI Spike Report

Write the complete spike report to:
  artifacts\results\model23-cli-spike-YYYYMMDD.md

This is the source of truth for Phase 2 Terraform.
It must contain:
  - All resource IDs created and modified
  - Every command run (success and failure)
  - All connectivity test results with actual output
  - tcpdump evidence that VPC-B is in the traffic path
  - Appliance mode symmetry test results (10 requests)
  - Issues found and workarounds used
  - Terraform resource creation order (derived from
    any dependency errors encountered)
  - Known issues to add to skill files

### Output 2 — Copilot Terraform Prompt

Write a ready-to-use Copilot prompt to:
  artifacts\COPILOT-MODEL23-PHASE2-TERRAFORM-GENERATED.md

This prompt must be specific to what was actually built —
not generic. Use the actual resource IDs from this session.

The prompt must tell Copilot to:

1. Read artifacts\skills\terraform-skill.md
2. Read artifacts\results\model23-cli-spike-YYYYMMDD.md
3. Read the current network module:
     terraform-aws\modules\network\main.tf
4. Import these specific resources (list actual IDs):
     - TGW1 Spoke RT: [actual ID]
     - TGW2 Spoke RT: [actual ID]
     - [all association and route resources]
5. Add these specific Terraform resources (with actual IDs
   as reference values for validation):
     - aws_ec2_transit_gateway_route_table.spoke for each TGW
     - aws_ec2_transit_gateway_route_table_association (spoke VPCs)
     - aws_ec2_transit_gateway_route (spoke default → VPC-B)
     - aws_ec2_transit_gateway_route (firewall RT routes)
     - appliance_mode_support = "enable" on VPC-B attachments
6. Run terraform plan and check:
     - 0 destroys of VPCs, TGWs, or attachments
     - Changes match what was built via CLI
7. Run terraform fmt and validate
8. Write a plan review report
9. Mark as READY FOR OPERATOR APPLY or STOP

Include the actual commands Q Developer ran and the outputs
it received so Copilot knows exactly what to codify.

---

## RULES FOR THIS SESSION

- Never skip a verification step
- Never assume a command succeeded without reading output
- Always log failures completely including the error message
- For any unexpected error: stop, diagnose, explain to operator
- Do not run terraform in this session
- Do not modify any Terraform files in this session
- If anything looks wrong with the architecture: ask operator
  before proceeding — you may have found a design issue

---

## HOW TO HANDLE FAILURES

If a command fails with a known error:
  RouteAlreadyExists → log as "already present", continue
  ResourceNotFound   → check tag filter, retry with describe
  DuplicateAssociation → check current RT, may already be correct
  DependencyViolation → record dependency, note order for Terraform

If a command fails with unknown error:
  STOP. Print the full error. Diagnose. Ask operator.
  Do not guess and retry blindly.

---

## START

Begin by reading the three part files and the skill files.
Then summarize for operator confirmation.
Then ask: "Ready to begin Part 1? (yes/no)"