# Network Troubleshooting Status Report
Date: 2026-04-04

Basis: document review only. No live AWS CLI, Reachability Analyzer, SSH, or Terraform commands were run for this report.

## Desired State

- A1 Windows browser can reach B1 and C1.
- A2 Linux jump host can reach B1 and C1 via curl and SSH.

## What the Reviewed Docs Confirm

- A1 (`10.0.1.10`) and A2 (`10.0.1.20`) are in VPC-A, and A2 is the SSH jump host.
- VPC-A to NLB-B is the documented management browser test path.
- VPC-A to NLB-C on TCP 443 is the documented AppGate Portal path for C1.
- The dedicated C1 incident playbook defines the expected C1 path as A1 -> VPC-A -> TGW1 -> NLB-C -> C1.
- If A2 can reach C1 by curl while A1 cannot reach it in Chrome, the troubleshooting logic treats that as an A1 Windows/browser issue rather than a core network issue.

## Current Status

- No live pass/fail evidence is present in the reviewed files for:
  - A1 -> B1 in browser
  - A1 -> C1 in browser
  - A2 -> B1 via curl/SSH
  - A2 -> C1 via curl/SSH
- The supplied runbook is detailed for diagnosing C1 reachability from A1, but no completed diagnosis output is included.
- B1 is only referenced indirectly through NLB-B tests and egress notes. The reviewed docs do not clearly define a B1 host, IP address, or a dedicated A2 -> B1 SSH procedure.

## Blockers and Inconsistencies

- `artifacts/Seasoning.md` is a general operator handoff that restricts work to `terraform init` and `terraform plan`, and explicitly says not to run AWS CLI commands.
- `artifacts/COPILOT-DIAGNOSE-C1-UNREACHABLE.md` and the network troubleshooting toolbox require AWS CLI `describe`/`search` commands plus Reachability Analyzer, and explicitly say not to run Terraform during diagnosis.
- The C1 incident doc says the mandatory first step is to read `artifacts/skills/network-troubleshooting/SKILL.md`, but the folder currently contains only `network-troubleshooting.md`.

## Working Interpretation

- The C1 path is well documented and diagnosable, but it is not yet proven healthy.
- The B1 path is part of the desired end state, but the supplied documentation does not fully specify it.
- If A2 -> C1 succeeds while A1 -> C1 fails, the highest-probability next area is A1 browser configuration, proxy behavior, certificate handling, or DNS resolution of the NLB-C DNS name.

## Recommended Next Steps

1. Confirm whether `artifacts/Seasoning.md` is meant to govern this network troubleshooting session, or only Terraform execution sessions.
2. Clarify what `B1` refers to in this lab: a specific instance, an NLB-B target, or the Palo management endpoint.
3. After those two items are clarified, collect live evidence:
   - For C1, follow the existing sequence: NLB target health -> TGW routes -> Reachability Analyzer -> NACL -> security group -> SSM/nginx.
   - For B1, create or identify the equivalent validation checklist so the full desired state can be tested consistently.
