# Copilot Instructions — TGW Segmentation Lab

## ⚠️ MANDATORY: READ THIS FILE COMPLETELY BEFORE TAKING ANY ACTION

You are assisting with the deployment and validation of a dual-Transit-Gateway AWS segmentation
lab. This lab simulates a real DoD-adjacent cloud architecture used in an IL4/IL5 GovCloud
environment. Treat all work as if it will be reviewed by a senior cloud security engineer.

---

## 0. Workflow — Follow This Order Every Time

```
1. READ   → Read this file and all skill files before doing anything
2. SEARCH → Web-search to validate any command, resource, or config before running it
3. PLAN   → State what you are about to do and why
4. EXECUTE → Run the command or apply the change
5. VERIFY → Confirm the result is correct
6. REPORT → Write your findings to artifacts/results/
```

Do not skip steps. Do not run a command you have not first validated via web search.

---

## 1. Project Context

### What This Lab Is

A Terraform-managed AWS lab that simulates a segmented cloud architecture with:

- **VPC-A** (`10.0.0.0/16`) — Cloud Host / Management VPC
  - `A1`: Windows Server 2022 (`t3.medium`) — RDP access, Chrome browser, used to reach B1/C1 via HTTP
  - `A2`: Amazon Linux 2023 (`t3.micro`) — SSH jump box, used to SSH into B1 and C1

- **VPC-B** (`10.1.0.0/16`) — Palo Alto NGFW simulation
  - `B1`: Amazon Linux 2023 (`t3.micro`) — nginx serving a styled HTML page

- **VPC-C** (`10.2.0.0/16`) — AppGate SDP simulation
  - `C1`: Amazon Linux 2023 (`t3.micro`) — nginx serving a styled HTML page

- **VPC-D** (`10.3.0.0/16`) — Customer VPC
  - `D1`: Amazon Linux 2023 (`t3.micro`) — curl/SSH test client

### Transit Gateway Architecture

```
TGW-1 (MGMT):      VPC-A <-> VPC-B <-> VPC-C
TGW-2 (CUSTOMER):  VPC-D <-> VPC-B <-> VPC-C

VPC-A and VPC-D share NO transit gateway.
There is physically no network path between them.
```

### Intended Traffic Flows

| Source | Destination | Expected | Mechanism |
|--------|-------------|----------|-----------|
| A1 (Chrome) | B1:80 | ✅ PASS | TGW-1 MGMT RT |
| A1 (Chrome) | C1:80 | ✅ PASS | TGW-1 MGMT RT |
| A2 (SSH) | B1:22 | ✅ PASS | TGW-1 MGMT RT |
| A2 (SSH) | C1:22 | ✅ PASS | TGW-1 MGMT RT |
| A1/A2 | D1 | ❌ FAIL | No shared TGW |
| D1 (curl) | B1:80 | ✅ PASS | TGW-2 CUSTOMER RT |
| D1 (curl) | C1:80 | ✅ PASS | TGW-2 CUSTOMER RT |
| D1 | A1/A2 | ❌ FAIL | No shared TGW |
| B1 (SSH) | D1:22 | ✅ PASS | TGW-2 return path |
| B1 | C1 | ✅ PASS | B<->C unrestricted |

### Security Layers

Each VPC has both a Security Group (stateful) and an explicit NACL (stateless).
Every NACL explicitly allows ephemeral ports (1024-65535) on return paths.
NACLs are the outer ring; Security Groups are the inner ring.

---

## 2. File Structure

```
C:\Users\Willi\projects\Labs\terraform-aws/
├── C:\Users\Willi\projects\Labs\terraform-aws\environments\dev\main.tf              # All resources: VPCs, subnets, TGWs, SGs, NACLs, instances
├── C:\Users\Willi\projects\Labs\terraform-aws\environments\dev\variables.tf         # region, public_key
├── C:\Users\Willi\projects\Labs\terraform-aws\environments\dev\outputs.tf           # IPs, RDP password command, test matrix
├── C:\Users\Willi\projects\Labs\terraform-aws\environments\dev\README.md           # Human-readable deploy guide
└── C:\Users\Willi\projects\Labs\artifacts
    ├── copilot-instructions.md   ← YOU ARE HERE
    ├── skills/
    │   ├── terraform/SKILL.md    # Terraform patterns and validation rules
    │   └── aws-cli/SKILL.md      # AWS CLI patterns and validation rules
    └── results/                  # Write all reports here after each task
```

---

## 3. Security Standards You Must Enforce

Before running or applying anything, validate against these standards:

### Terraform
- All resources must have `Name` tags
- No hardcoded credentials anywhere — use variables or instance profiles
- `default_route_table_association = "disable"` and `default_route_table_propagation = "disable"` must be set on all TGWs
- Security Groups must not use `0.0.0.0/0` for ingress except for public-facing ports (RDP:3389, SSH:22) on bastion/jump boxes
- NACLs must be explicit — never rely on the AWS default NACL
- Egress rules must be scoped to known CIDRs where possible, not `0.0.0.0/0`
- `associate_public_ip_address = true` only on A1 and A2 — all other instances are private

### AWS CLI
- Always use `--region` explicitly — never rely on environment defaults
- Always confirm resource state after creation (`describe`, `get`, `list`)
- Never delete a resource without first confirming what depends on it
- Use `--dry-run` where supported before destructive operations

### General
- Web-search to confirm any AWS resource argument that may have changed since your training cutoff
- Check the Terraform AWS provider changelog if using any resource introduced after 2023
- Flag any finding that would fail a CIS AWS Foundations Benchmark check

---

## 4. Validation Checklist Before `terraform apply`

Run through this before every apply:

- [ ] `terraform fmt` — no formatting errors
- [ ] `terraform validate` — no syntax errors
- [ ] `terraform plan` — review all changes, confirm no unexpected destroys
- [ ] Web-search: confirm AMI filter patterns for `al2023-ami-*-x86_64` are still current
- [ ] Web-search: confirm `Windows_Server-2022-English-Full-Base-*` AMI name pattern is current
- [ ] Web-search: confirm TGW attachment arguments haven't changed in the provider version in use
- [ ] Confirm all NACLs have ephemeral port rules on both inbound and outbound
- [ ] Confirm no SG has `0.0.0.0/0` ingress on ports other than 22 and 3389

---

## 5. Validation Checklist After `terraform apply`

Run these AWS CLI checks after every deployment:

```bash
# Confirm TGW route tables have correct static routes
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <TGW1_RT_ID> \
  --filters Name=state,Values=active \
  --region <REGION>

# Confirm VPC route tables have TGW entries
aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values=<VPC_A_ID> \
  --region <REGION>

# Confirm SG rules on B1
aws ec2 describe-security-groups \
  --group-ids <SG_B_ID> \
  --region <REGION>

# Confirm NACL rules on subnet-b
aws ec2 describe-network-acls \
  --filters Name=association.subnet-id,Values=<SUBNET_B_ID> \
  --region <REGION>

# Confirm instances are running
aws ec2 describe-instances \
  --filters Name=tag:Name,Values=lab-* Name=instance-state-name,Values=running \
  --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],InstanceId,PrivateIpAddress,PublicIpAddress,State.Name]' \
  --output table \
  --region <REGION>
```

---

## 6. Connectivity Tests to Run

After deployment, run all of these and record pass/fail in results/:

### From A2 (Linux SSH jump — run via SSH)
```bash
# SSH tests
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@<B1_IP>   # expect: PASS
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@<C1_IP>   # expect: PASS
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@<D1_IP>   # expect: FAIL (timeout)

# HTTP tests
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://<B1_IP>   # expect: 200
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://<C1_IP>   # expect: 200
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://<D1_IP>   # expect: 000 (no route)

# Ping tests
ping -c 3 <B1_IP>   # expect: PASS
ping -c 3 <C1_IP>   # expect: PASS
ping -c 3 <D1_IP>   # expect: FAIL
```

### From B1 (hop to D1 — run via SSH into B1 first)
```bash
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@<D1_IP>   # expect: PASS
ping -c 3 <D1_IP>                                               # expect: PASS
```

### From D1 (via B1 hop — run via SSH into D1 via B1)
```bash
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://<B1_IP>   # expect: 200
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://<C1_IP>   # expect: 200
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://<A2_IP>   # expect: 000 (no route)
```

### From A1 (Windows — manual browser test)
```
Open Chrome → http://<B1_IP>  → should load Palo Alto NGFW page
Open Chrome → http://<C1_IP>  → should load AppGate SDP page
Open Chrome → http://<D1_IP>  → should time out
```

---

## 7. Reporting Requirements

After completing any task, write a report to `artifacts/results/`.

### Filename format
```
artifacts/results/YYYY-MM-DD_<task-name>.md
```

### Required report sections
```markdown
# Task: <description>
Date: YYYY-MM-DD
Performed by: GitHub Copilot

## Web Search Validations
- [ ] <what you searched> → <what you confirmed>

## Actions Taken
1. <command or change>
   Result: <output or confirmation>

## Connectivity Test Results
| Test | Expected | Actual | Pass/Fail |
|------|----------|--------|-----------|

## Issues Found
- <any deviations, unexpected results, or security concerns>

## Recommendations
- <any suggested improvements>
```

---

## 8. What You Must NOT Do

- Do not run `terraform destroy` without explicit instruction
- Do not modify `main.tf` without running `terraform plan` first and showing the plan
- Do not skip the web search validation step
- Do not assume AMI IDs — always use `data` sources with filters
- Do not hardcode region — always use `var.region`
- Do not open `0.0.0.0/0` on any port other than 22 (A2) and 3389 (A1)
- Do not add VPC peering between VPC-A and VPC-D — this breaks the segmentation design
- Do not rely on default TGW route tables — they are explicitly disabled in this config

---

## 9. Skills Reference

Read these before working with the respective tools:

- **Terraform**: `artifacts/skills/terraform/SKILL.md`
- **AWS CLI**: `artifacts/skills/aws-cli/SKILL.md`

## Session 2026-04-04 - Operational Lessons

### Skill File Paths
Local skill files use flat filenames, not subdirectory `SKILL.md` paths:
- CORRECT: `artifacts/skills/terraform-skill.md`
- CORRECT: `artifacts/skills/aws-cli-skill.md`
- CORRECT: `artifacts/skills/network-troubleshooting/SKILL.md`
- WRONG: `artifacts/skills/terraform/SKILL.md`

### PowerShell Stop-Parsing
Always use `terraform --%` for Terraform commands in PowerShell:

```powershell
terraform --% init -backend-config=backend.hcl
terraform --% plan -out=tfplan -no-color
terraform --% apply tfplan
```

### Destroy Count Threshold
The safe destroy threshold for the full refactor is `135`.
The hard constraint is:
- no `aws_vpc`
- no `aws_ec2_transit_gateway`
- no `aws_ec2_transit_gateway_vpc_attachment`
in the destroy list.

Raw destroy count alone is not a safe/unsafe signal for this architecture change.

### npx skills add requires --yes flag
Interactive prompts break non-interactive Copilot sessions.
Always use:

```bash
npx skills add --yes <skill-path>
```

### MCP servers not available in Codex environment
The HashiCorp Terraform MCP and AWS Labs Terraform MCP servers may be configured
in VS Code settings, but they are not available in the Codex agent environment.
Proceed without them and use web search for provider documentation instead.
