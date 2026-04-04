# Task: Skill-guided network validation
Date: 2026-04-04
Performed by: Codex

## Scope
Validated the live lab by following the local guide at [network-troubleshooting.md](C:/Users/Willi/projects/Labs/artifacts/skills/network-troubleshooting/network-troubleshooting.md).

This was a diagnosis-only pass using read commands, SSH checks, and Reachability Analyzer.

## Tools Run
- `Tool 1: NLB Target Health Check`
- `Tool 2: VPC Reachability Analyzer`
- `Tool 4: TGW Route Analyzer`
- `Tool 5: NACL Inspector`
- `Tool 6: Security Group Auditor`
- `Tool 7: Instance-side service check via SSH`
- `Tool 9: End-to-End curl matrix from A2`

## Findings
1. `NLB-C` control plane is healthy.
   - `lab-nlb-c-appgate-portal-80` target `10.2.2.10:80` is `healthy`.
   - `lab-nlb-c-appgate-portal-443` target `10.2.2.10:443` is `healthy`.

2. `NLB-B` control plane is not healthy.
   - `lab-nlb-b-palo-trust-80` target `10.1.2.10:80` is `unhealthy`.
   - `lab-nlb-b-palo-trust-443` target `10.1.2.10:443` is `unhealthy`.
   - AWS reason on both was `Target.FailedHealthChecks`.
   - Read-only instance checks on `B1` found:
   - `nginx` is `inactive`
   - no custom source-based `ip rule` entries are present
   - `lab-multi-eni.service` is `failed`
   - the failure log shows `/etc/iproute2/rt_tables: No such file or directory`
   - this explains why the trust-side NLB target is not healthy

3. The direct private management/browser path from VPC A is working.
   - From `A2`, these returned `200`:
   - `https://10.1.3.10`
   - `http://10.2.2.10`
   - `https://10.2.2.10`
   - `https://10.2.3.10`
   - `https://10.2.4.10`
   - `http://10.3.1.10` returned `000`, which matches the intended A-to-D isolation.

4. The NLB DNS names resolve from `A2`, but the data path still fails.
   - `lab-nlb-b-palo-trust-0beea7bacf76930b.elb.us-east-1.amazonaws.com` resolved to `10.1.1.196`
   - `lab-nlb-c-appgate-portal-92573dd5f65ddead.elb.us-east-1.amazonaws.com` resolved to `10.2.1.51`
   - From `A2`, both `http` and `https` to both NLB DNS names returned `000`

5. The route tables needed for VPC A to VPC C are present.
   - `lab-rt-a` has `10.2.0.0/16 -> tgw-0182ba880fd0f5577`
   - `lab-rt-c-dmz` has `10.0.0.0/16 -> tgw-0182ba880fd0f5577`
   - `lab-rt-c-portal` has `10.0.0.0/16 -> tgw-0182ba880fd0f5577`

6. The relevant NACLs now contain the expected east-west rules.
   - `nacl-a` includes VPC-A ingress for `80`, `443`, and `8443` from `10.0.0.0/16`, plus return ephemeral rules from `10.1.0.0/16` and `10.2.0.0/16`
   - `nacl-c-dmz` includes ingress from VPC A on `443`, `8443`, and `22`, plus return ephemeral rules from the portal/gateway/controller subnets
   - `nacl-c-dmz` also now includes egress `tcp/80` to `10.2.2.0/24`
   - `nacl-c-portal` includes ingress from VPC A on `80`, `443`, and `22`, plus ingress from `10.2.1.0/24` on `80/443`

7. `C1` security groups and local service state are healthy.
   - `lab-sg-c1-portal` allows:
   - `tcp/80` from `10.2.1.0/24`
   - `tcp/443` from `10.2.1.0/24`
   - `tcp/80` from `10.0.0.0/16`
   - `tcp/443` from `10.0.0.0/16`
   - `tcp/8443` from `10.0.0.0/16`
   - `tcp/22` from `10.0.0.0/16`
   - `icmp` from `10.0.0.0/8`
   - On `C1`, `nginx` is active, listening on `80` and `443`, and both `http://127.0.0.1` and `https://127.0.0.1` return `200`

8. Reachability Analyzer splits the `C1` issue into two different results.
   - `A1 ENI -> NLB-C ENI :443` returned `NetworkPathFound=false`
   - Explanation code was `NO_ROUTE_TO_DESTINATION`
   - `NLB-C ENI -> C1 ENI :443` returned `NetworkPathFound=true`

## Interpretation
- The skill-guided checks confirm that the direct VPC-A-to-instance access path is working for the management/browser targets in VPC B and VPC C.
- The skill-guided checks do **not** confirm the intended NLB-based browser path yet.
- For VPC C, the target and instance side are healthy, but the first hop to `NLB-C` still fails from VPC A.
- For VPC B, `NLB-B` is not healthy at the target group level, so that path is not ready.
- For VPC B, the immediate root cause is on-instance bootstrap failure on `B1`, not a missing TGW route.

## Bottom Line
The current lab is healthy for:
- `A1/A2 -> B1 mgmt`
- `A1/A2 -> C1`
- `A1/A2 -> C2`
- `A1/A2 -> C3`
- `A1/A2 -X-> D1` isolation

The current lab is **not yet healthy** for the guide's NLB-based validation path:
- `VPC A -> NLB-B`
- `VPC A -> NLB-C`

## Status
STOP — NLB-based path still requires operator review
