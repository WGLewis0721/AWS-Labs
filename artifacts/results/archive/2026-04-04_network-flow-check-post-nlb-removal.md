# Network Flow Check After NLB Removal
Date: 2026-04-04

Basis: repo review plus existing `artifacts/results/2026-04-04_netcheck-final.txt`. No new live AWS, SSH, or Terraform commands were run for this follow-up.

## Current Intended Flow

The current lab no longer uses internal NLB-B or NLB-C for the management and validation path.

- Laptop -> A1 over RDP -> Chrome -> direct private HTTPS targets
- Laptop -> A2 over SSH -> direct private SSH/HTTPS targets
- A2 -> B1 management interface at `10.1.3.10`
- A2 -> C1 portal at `10.2.2.10`
- B1 -> D1 remains the validated administrative hop for customer-segment access

## Current Source of Truth

The newest infrastructure README now says:

- `A1` and `A2` can reach `B1` and `C1`
- internal validation uses private instance IPs directly
- the lab does not depend on internal NLBs
- the direct private-IP targets replace the older internal NLB checks

## Flow Status

### A2 -> B1

Status: PASS

Evidence from the saved netcheck output:

- ICMP to `10.1.3.10` reachable
- TCP `22` open
- TCP `443` open
- HTTPS returned `200`
- SSH succeeded and returned hostname `b1-paloalto`

### A2 -> C1

Status: PASS

Evidence from the saved netcheck output:

- ICMP to `10.2.2.10` reachable
- TCP `22` open
- TCP `80` open
- TCP `443` open
- HTTP returned `200`
- HTTPS returned `200`
- SSH succeeded and returned hostname `c1-portal`

### A1 -> B1 / C1

Status: Intended and documented as direct browser access, but not re-verified in this follow-up from the terminal.

Documented expected behavior:

- A1 Chrome -> B1 HTTPS allowed
- A1 Chrome -> C1 HTTPS allowed
- browser tests should use direct private-IP targets rather than NLB DNS names

## Supporting Routing State

The saved netcheck output also confirms:

- no internal `NLB-B` or `NLB-C` load balancers remain
- VPC-A has a route for `10.2.0.0/16` to a transit gateway
- VPC-A subnet NACL includes the direct-access rules needed for the simplified design
- c-dmz NACL still includes the rule permitting HTTP toward the portal subnet

## Conclusion

The management and validation flow has changed from:

- A1/A2 -> internal NLB -> target instance

to:

- A1/A2 -> direct private instance IP

For the current simplified lab, the flow is healthy for the terminal-verifiable paths:

- A2 -> B1 management (`10.1.3.10`) via SSH/HTTPS
- A2 -> C1 portal (`10.2.2.10`) via SSH/HTTP/HTTPS

The remaining gap is documentation drift:

- `artifacts/COPILOT-DIAGNOSE-C1-UNREACHABLE.md`
- `artifacts/skills/network-troubleshooting/network-troubleshooting.md`

still describe an NLB-based path that no longer matches the live environment.
