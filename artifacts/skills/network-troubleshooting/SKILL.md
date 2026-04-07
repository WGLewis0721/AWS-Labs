# Network Troubleshooting Skill

Canonical workflow content lives in:
`network-troubleshooting.md`

Use that file for the full workflow.

## Current Defaults

Assume all of the following unless the operator explicitly says the design changed:

- no internal validation load balancers
- direct private-IP validation from `A1` and `A2`
- one public customer-entry load balancer only
- no custom Route 53 resources
- `D1` must remain unreachable from VPC-A
- **Model 2+3 two-table TGW routing is active** — all inter-VPC traffic transits VPC-B (`10.1.2.0/24`) before reaching its destination
- appliance mode is enabled on both VPC-B TGW attachments

## First Response Order

1. Run the canonical A2 netcheck or its SSM document first.
2. If A2 succeeds and A1 fails, treat it as an A1 browser or certificate problem first.
3. If direct private-IP validation fails, inspect route tables, NACLs, and SGs in that order.
4. For Model 2+3 paths, check `nacl-b-trust` and destination SG `10.1.2.0/24` rules before using Reachability Analyzer.
5. Use Reachability Analyzer only after the basic path checks.
6. Note: Reachability Analyzer cannot model TGW source IP substitution for multi-hop inspection paths. A `False` result for D1→C1 via TGW inspection is a known RA limitation, not proof of a real failure.

### TOOL 10 - Two-Table TGW Pattern Verifier

Use after deploying or troubleshooting combined Model 2+3.

Key checks:

1. Spoke VPCs are associated with the Spoke RT, not the Firewall RT.
2. VPC-B inspection attachments are associated with the Firewall RT.
3. Each Spoke RT has `0.0.0.0/0` to the VPC-B attachment.
4. Each Firewall RT has specific routes back to its spoke VPCs.
5. Appliance mode is enabled on both VPC-B TGW attachments.
6. Destination NACLs and SGs allow traffic from `10.1.2.0/24`, the TGW attachment subnet.
7. Ten consecutive `curl -sk https://10.2.2.10` requests from A2 should all return `200`.

Do not use B1 OS-level `tcpdump` as a proof of TGW inspection-path transit. TGW uses AWS-managed attachment ENIs for transit, so B1 can show zero packets while the inspected path is working.

### 2025-07-14 - Model 2+3 cutover: NACLs must allow traffic from TGW attachment subnet

Symptom: C1 HTTP timed out immediately after TGW association cutover to spoke/firewall RTs.

Root cause:
- NACLs were written for direct VPC-to-VPC flows. After cutover, all traffic transits `10.1.2.0/24` (VPC-B trust, TGW attachment subnet). `nacl-b-trust` was missing port 80 ingress/egress, and `nacl-c-dmz`/`nacl-c-portal` were missing ingress from `10.1.2.0/24`.

Required additions:
- `nacl-b-trust` ingress `92` tcp `80` from `10.0.0.0/16`
- `nacl-b-trust` egress `101` tcp `80` to `10.2.0.0/16`
- `nacl-c-dmz` ingress `99` tcp `80` from `10.1.2.0/24`
- `nacl-c-dmz` ingress `100` tcp `443` from `10.1.2.0/24`
- `nacl-c-portal` ingress `93` tcp `80` from `10.1.2.0/24`
- `nacl-c-portal` ingress `94` tcp `443` from `10.1.2.0/24`
- `nacl-c-portal` egress `89` tcp `1024-65535` to `10.1.2.0/24`

### 2025-07-14 - Model 2+3 cutover: SGs on C1/C2/C3 must allow ingress from TGW attachment subnet

Symptom: Reachability Analyzer showed `ENI_SG_RULES_MISMATCH` for D1→C1 path after cutover.

Root cause:
- SGs on C1, C2, C3 allowed `10.3.0.0/16` (VPC-D) directly, but after cutover traffic arrives sourced from TGW ENI IPs in `10.1.2.0/24`.

Required additions to each destination SG:
- ingress tcp `443` from `10.1.2.0/24` with description "HTTPS transit from VPC-B trust (TGW inspection path)"

### 2025-07-14 - tcpdump on inspection instance does not see TGW transit traffic

Symptom: tcpdump on B1 showed 0 packets while curl to C1 succeeded.

Root cause:
- TGW uses its own managed ENIs (`eni-00921ddc14d7988d2` at `10.1.2.146`, `eni-0b021d5d9cd35c932` at `10.1.2.184`) for transit. These are not visible at the B1 instance OS level. This is expected behavior for TGW inspection architecture.

Fix:
- Use Reachability Analyzer to confirm the inspection path. tcpdump is not a valid test for TGW transit visibility.

### 2025-07-14 - Reachability Analyzer false negative for multi-hop TGW inspection paths

Symptom: D1→C1 Reachability Analyzer showed `False` even after all NACLs and SGs were correct.

Root cause:
- RA evaluates destination SGs using the original source IP (e.g. `10.3.1.10`), not the TGW ENI IP (`10.1.2.184`). It cannot model TGW source IP substitution for multi-hop paths.

Fix:
- This is a known RA limitation. Confirm actual traffic works via curl/ping. Do not treat RA `False` for TGW inspection paths as proof of a real failure.

### 2026-04-07 - TGW route table association swap can cause a brief gap

Symptom: Short connectivity loss while moving a TGW attachment from one route table to another.

Root cause:
- TGW route table association changes are not atomic. The old association is removed before the new association becomes active.

Fix:
- Prefer the Terraform-codified association model.
- If a manual swap is unavoidable, plan for a brief maintenance window and verify the Spoke/Firewall associations immediately afterward.

### 2026-04-04 - lab-rt-b-untrust missing return routes

Symptom: ping to Palo UNTRUST worked but TCP failed.

Root cause:
- `lab-rt-b-untrust` was missing return routes for VPC-A, VPC-C, and VPC-D.

Required routes:
- `10.0.0.0/16 -> TGW1`
- `10.2.0.0/16 -> TGW1`
- `10.3.0.0/16 -> TGW2`

### 2026-04-04 - VPC-C instances missing centralized egress

Symptom: package installation failed on `C1`, `C2`, and `C3`.

Root cause:
- VPC-C route tables did not all have `0.0.0.0/0 -> TGW1`.

### 2026-04-04 - placeholder web server blocked nginx

Symptom: nginx failed to bind `80` or `443`.

Root cause:
- placeholder Python listeners were already bound to those ports.

### 2026-04-04 - nacl-a missing service-port return rules

Symptom: `A2 -> C1` HTTPS timed out even after the VPC-C NACLs looked correct.

Root cause:
- `A2` and the TGW attachment share subnet `a`, so `nacl-a` also needed the service-port return path.

Required rules:
- ingress `111` tcp `80`
- ingress `112` tcp `443`
- ingress `113` tcp `8443`
- egress `125` tcp `80`

### 2026-04-04 - nacl-c-dmz missing HTTP egress to C1

Symptom: `A2 -> C1` HTTP failed while other portions of the path looked healthy.

Root cause:
- `nacl-c-dmz` was missing egress rule `96` for `tcp/80 -> 10.2.2.0/24`.

### 2026-04-04 - A2 key permissions too open

Symptom:
- SSH warned about an unprotected private key file.

Fix:

```bash
chmod 600 ~/tgw-lab-key.pem
```

### 2026-04-04 - IMDSv2 broke naive local-IP checks

Symptom:
- old metadata `curl` commands returned nothing.

Fix:
- use IMDSv2 token flow
- or derive the IP from `ip route`

### 2026-04-04 - old reports were polluted by removed load balancers

Symptom:
- scripts kept flagging legacy load-balancer failures that no longer mattered.

Root cause:
- troubleshooting logic still assumed the pre-refactor internal validation load-balancer model.

Fix:
- switch the default validation path to direct private IPs and keep the public customer-entry load balancer separate from operator-path checks
