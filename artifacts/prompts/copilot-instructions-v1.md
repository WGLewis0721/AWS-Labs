# Copilot Instructions - TGW Segmentation Lab

## Mandatory

Read this file, the relevant local skill files, and the task prompt before taking action.

Treat the lab as production-quality infrastructure work. The standard is correctness, repeatability, and minimal wasted operator time.

## Default Workflow

Use this order unless the task explicitly says otherwise:

1. Read only the files relevant to the task.
2. Verify whether the task is already done in AWS or in the repo.
3. Reuse existing scripts and prompts instead of rebuilding the workflow from scratch.
4. State the action briefly.
5. Execute.
6. Verify the result.
7. Write a concise report only if the task or session requires one.

Optimize for low-noise execution:

- skip already-completed steps once they are verified
- batch read-only inspection commands where possible
- use the canonical repo scripts instead of long ad hoc command sequences
- do not re-open resolved architecture debates unless the live state disagrees with the repo

## Current Architecture

This is the current working architecture. Future sessions should assume this unless the user says the design has changed.

- VPC-A `10.0.0.0/16`
  - `A1` Windows RDP and browser host
  - `A2` Linux SSH and bootstrap host
- VPC-B `10.1.0.0/16`
  - `B1` Palo Alto simulation with three ENIs
  - operator validation target is `10.1.3.10`
- VPC-C `10.2.0.0/16`
  - `C1` portal `10.2.2.10`
  - `C2` gateway `10.2.3.10`
  - `C3` controller `10.2.4.10`
- VPC-D `10.3.0.0/16`
  - `D1` customer `10.3.1.10`
- `TGW1` connects A, B, and C
- `TGW2` connects B, C, and D
- VPC-A must not have direct reachability to VPC-D

Architecture facts that matter operationally:

- internal validation load balancers are not part of the current design
- operator validation from VPC-A uses direct private IPs
- one public customer-entry load balancer still exists in VPC-B untrust
- Route 53 is not part of the custom lab architecture
- `alb_dns_name` is the compatibility output name for the public customer-entry load balancer

## Canonical Skill Paths

Use these local skill files:

- `artifacts/skills/terraform-skill.md`
- `artifacts/skills/aws-cli-skill.md`
- `artifacts/skills/network-troubleshooting/SKILL.md`

Do not use the old nonexistent paths such as `artifacts/skills/terraform/SKILL.md`.

## Canonical Script Paths

Use these before inventing a new workflow:

- deploy: `artifacts/scripts/deploy.ps1`
- teardown: `artifacts/scripts/teardown.ps1`
- A2 netcheck: `artifacts/scripts/netcheck.sh`
- A1 netcheck: `artifacts/scripts/netcheck-a1.ps1`
- SSM docs:
  - `artifacts/scripts/ssm-netcheck-a1.yml`
  - `artifacts/scripts/ssm-netcheck-a2.yml`

## Deployment Rules

For a fresh or rebuilt environment, prefer:

```powershell
.\artifacts\scripts\deploy.ps1 -Environment dev
```

Reason:

- it seeds S3 assets
- creates or reuses golden AMIs
- writes the AMI override file
- applies Terraform in phases
- attaches SSM profiles
- bootstraps nginx through A2
- runs SSM netchecks

Do not default to raw `terraform apply` when the user asks for a deployment outcome.

## Terraform Rules

Use PowerShell stop-parsing for Terraform:

```powershell
terraform --% init -backend-config=backend.hcl
terraform --% plan -out=tfplan -no-color
terraform --% apply tfplan
```

Before apply:

- run `terraform fmt`
- run `terraform validate`
- review the destroy set

Hard stop resources in destroy or replace:

- `aws_vpc`
- `aws_ec2_transit_gateway`
- `aws_ec2_transit_gateway_vpc_attachment`

Raw destroy count alone is not enough. This lab has already had a safe `131`-destroy refactor driven by per-subnet route-table and NACL replacement.

## Validation Rules

Primary operator validation targets from VPC-A:

- `https://10.1.3.10`
- `http://10.2.2.10`
- `https://10.2.2.10`
- `https://10.2.3.10`
- `https://10.2.4.10`

Negative control:

- `10.3.1.10` must fail from VPC-A

Do not default to legacy internal DNS validation paths. If a prompt or report still references them, treat that as stale guidance.

Prefer SSM netchecks for routine validation:

- `lab-netcheck-a1`
- `lab-netcheck-a2`

## AWS CLI Rules

- always use `--region`
- prefer `--output json` in PowerShell
- redirect large outputs to files under `artifacts/tmp` or `artifacts/results` when needed
- verify whether a manual fix already exists before re-running it

When a command is likely to be blocked by IAM on-instance, verify whether that is an expected role limitation before treating it as a broken lab.

## Lessons Learned That Must Persist

### Route tables

`lab-rt-b-untrust` must retain:

- `10.0.0.0/16 -> TGW1`
- `10.2.0.0/16 -> TGW1`
- `10.3.0.0/16 -> TGW2`

All VPC-C subnet route tables must retain:

- `0.0.0.0/0 -> TGW1`

### NACLs

`nacl-a` must retain:

- ingress `111` tcp `80`
- ingress `112` tcp `443`
- ingress `113` tcp `8443`
- egress `125` tcp `80`

`nacl-c-dmz` must retain:

- egress `96` tcp `80` to `10.2.2.0/24`

### Service validation

- `B1` is validated on `10.1.3.10`
- `C3` landing page validation is on `443`, not `8443`
- `C1` is the sensitive nginx/TLS bootstrap node

### Deploy optimization

- golden AMI reuse is part of the intended workflow
- S3-hosted bootstrap assets are part of the intended workflow
- SSM command documents are part of the intended workflow

## MCP And External Skill Notes

- `npx skills add` must use `--yes` in non-interactive sessions
- MCP servers may exist in editor settings but are not guaranteed in the Codex environment
- if MCP is unavailable, proceed with local files, existing scripts, AWS CLI, and web verification when required

## What Not To Do

- do not run `terraform destroy` unless explicitly asked
- do not assume Route 53, internal load balancers, or one-subnet-per-VPC designs are still current
- do not re-run a known manual fix without first checking whether it is already present
- do not spend tokens reading unrelated files when the task scope is narrower
