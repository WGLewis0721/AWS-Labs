# GitHub Copilot — TGW Segmentation Lab Handoff Prompt

Paste the following as your opening message to Copilot in the workspace
where the tgw-lab-v2/ directory lives.

---

## PROMPT (paste this exactly)

---

You are taking over a Terraform-managed AWS lab project. Before you do anything else,
read the following files completely and confirm you have read them:

1. `artifacts/copilot-instructions-v1.md` — master instructions, workflow, and constraints
2. `artifacts/skills/terraform/SKILL.md` — Terraform patterns and validation rules
3. `artifacts/skills/aws-cli/SKILL.md` — AWS CLI validation commands

**Do not take any action until you have read and confirmed all three files.**

Once you have read them, your task is to:

1. **Validate the Terraform code** in `main.tf` before applying it:
   - Run `terraform fmt`, `terraform validate`, and `terraform plan`
   - Web-search to confirm all AWS resource arguments and AMI filter patterns are current and correct
   - Web-search to confirm the configuration meets CIS AWS Foundations Benchmark standards
   - Flag any issues you find

2. **Apply the configuration** if validation passes:
   - Run `terraform apply`
   - Capture all output

3. **Validate the deployment** using AWS CLI:
   - Follow the post-apply checklist in `artifacts/copilot-instructions.md` section 5
   - Run all connectivity tests defined in section 6
   - Record all results

4. **Write a report** to `artifacts/results/YYYY-MM-DD_initial-deployment.md`:
   - Follow the report format defined in `artifacts/copilot-instructions.md` section 7
   - Include every web search you performed and what it confirmed
   - Include every test result with pass/fail
   - Include any issues found and your recommendations

The SSH key is `tgw-lab-key.pem`. The region is `us-east-1` unless you are told otherwise.

Start by reading the three files and confirming their contents back to me.

---

## What Copilot Has Access To

```
tgw-lab-v2/
├── main.tf                          # Full Terraform config (VPCs, TGWs, SGs, NACLs, instances)
├── variables.tf                     # region, public_key vars
├── outputs.tf                       # IPs, test matrix, RDP password command
├── README.md                        # Human deploy guide
└── artifacts/
    ├── copilot-instructions.md      # Master instructions
    ├── skills/
    │   ├── terraform/SKILL.md       # Terraform skill
    │   └── aws-cli/SKILL.md         # AWS CLI skill
    └── results/                     # Copilot writes reports here
```

## Architecture Summary (for your reference when reviewing Copilot's work)

```
TGW-1 (MGMT):      VPC-A (10.0.0.0/16) <-> VPC-B (10.1.0.0/16) <-> VPC-C (10.2.0.0/16)
TGW-2 (CUSTOMER):  VPC-D (10.3.0.0/16) <-> VPC-B (10.1.0.0/16) <-> VPC-C (10.2.0.0/16)

VPC-A and VPC-D share NO transit gateway — physically isolated.

A1 = Windows (RDP + Chrome) — browses to B1 and C1
A2 = Linux (SSH) — SSHes to B1 and C1
B1 = nginx (Palo Alto sim)
C1 = nginx (AppGate sim)
D1 = Linux client (curls B1 and C1 via TGW-2)
```

## Expected Test Results Copilot Should Report

| Test | Expected |
|------|----------|
| A2 SSH → B1 | ✅ PASS |
| A2 SSH → C1 | ✅ PASS |
| A2 SSH → D1 | ❌ FAIL (timeout) |
| A2 curl → B1:80 | ✅ 200 |
| A2 curl → C1:80 | ✅ 200 |
| A2 curl → D1:80 | ❌ 000 (no route) |
| B1 SSH → D1 | ✅ PASS |
| D1 curl → B1:80 | ✅ 200 |
| D1 curl → C1:80 | ✅ 200 |
| D1 curl → A2 | ❌ 000 (no route) |
| A1 Chrome → B1 | ✅ page loads |
| A1 Chrome → C1 | ✅ page loads |

If any PASS result comes back as FAIL, or any FAIL result comes back as PASS,
treat it as a security finding and have Copilot investigate and report the root cause.