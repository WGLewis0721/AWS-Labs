# Diagnose: Cannot Reach C1 From VPC-A

## Current Model

This playbook now assumes the simplified direct-access design.
Do not troubleshoot C1 through an internal NLB path.

Current expected path:

- `A1` browser -> `https://10.2.2.10`
- `A2` jump host -> `10.2.2.10` over SSH, HTTP, and HTTPS

Read first:
`artifacts/skills/network-troubleshooting/network-troubleshooting.md`

## Required Sequence

1. Run the canonical A2 validation script:
   - `artifacts/scripts/netcheck.sh`
2. If `C1` direct checks fail, inspect:
   - VPC-A route table to `10.2.0.0/16`
   - destination NACLs
   - destination security group
3. If routing and policy look correct, run Reachability Analyzer:
   - `A2 ENI -> C1 ENI :443`
4. If the network path is open, SSH to `C1` and check:
   - `nginx`
   - listeners on `80` and `443`
   - local `curl` on `http://localhost` and `https://localhost`
5. If `A2` succeeds but `A1` fails, treat it as a browser or certificate issue first.

## Rules

- Diagnosis only unless the operator explicitly changes the session scope
- Prefer read-only AWS CLI commands
- Do not use Terraform during diagnosis
- Document the first confirmed root cause and stop there

## Output

Write the report to:
`artifacts/results/YYYY-MM-DD_c1-unreachable-diagnosis.md`

Include:
- symptom
- exact validation command used
- first failing layer
- evidence
- recommended next action
