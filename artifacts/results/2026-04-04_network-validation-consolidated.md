# Network Validation Consolidated Report
Date: 2026-04-04
Status: READY - simplified direct-access lab validated

## Scope

This report is the canonical network status summary for the simplified
post-NLB lab design.

Supporting raw evidence:
- [2026-04-04_netcheck-final.txt](C:/Users/Willi/projects/Labs/artifacts/results/raw/2026-04-04_netcheck-final.txt)

Superseded exploratory reports were archived under:
- [archive](C:/Users/Willi/projects/Labs/artifacts/results/archive)

## Current Design

The live lab no longer uses internal `NLB-B` or `NLB-C` for operator
validation.

Validated operator paths now are:
- `A1` browser -> direct private HTTPS targets
- `A2` jump host -> direct private SSH and HTTP/S targets
- `A2 -X-> D1` remains blocked by design

Primary direct targets:
- `B1` mgmt: `10.1.3.10`
- `C1` portal: `10.2.2.10`
- `C2` gateway: `10.2.3.10`
- `C3` controller: `10.2.4.10`
- `D1` customer: `10.3.1.10`

## Final Validation Results

### VPC-A self check

- `A2` confirmed as `10.0.1.20`
- `A2` internet access works
- `A2` public egress observed as `44.204.129.98`
- shared NAT gateway EIP for private instances is `98.94.212.42`

### VPC-B from VPC-A

- `A2 -> 10.1.3.10` ping: PASS
- `A2 -> 10.1.3.10:22` SSH: PASS
- `A2 -> 10.1.3.10:443` HTTPS: PASS
- hostname returned: `b1-paloalto`

### VPC-C from VPC-A

- `A2 -> 10.2.2.10` SSH, HTTP, HTTPS: PASS
- `A2 -> 10.2.3.10` SSH, HTTPS: PASS
- `A2 -> 10.2.4.10` SSH, HTTPS: PASS
- `C1` local nginx checks on `localhost:80` and `localhost:443`: PASS

### VPC-D isolation

- `A2 -> 10.3.1.10` ping: BLOCKED as expected
- `A2 -> 10.3.1.10:80`: BLOCKED as expected

### Infrastructure sanity

- internal `NLB-B` absent: PASS
- internal `NLB-C` absent: PASS
- VPC-A route table includes `10.2.0.0/16` to transit gateway: PASS
- `nacl-a` includes direct-access rules `111`, `112`, `113`, `125`: PASS
- `nacl-c-dmz` includes rule `96`: PASS

## Important Notes

- The `A2` instance role does not have `ec2:SearchTransitGatewayRoutes`.
- A failed `search-transit-gateway-routes` command from `A2` should be treated
  as an IAM limitation, not as proof of a routing failure.
- For this lab, direct path success plus VPC route-table inspection is the
  authoritative routing proof available from the current operator context.

## Operator Guidance

Use these direct browser targets from `A1`:
- `https://10.1.3.10`
- `https://10.2.2.10`
- `https://10.2.3.10`
- `https://10.2.4.10`

Use these direct SSH targets from `A2`:
- `ssh -i tgw-lab-key.pem ec2-user@10.1.3.10`
- `ssh -i tgw-lab-key.pem ec2-user@10.2.2.10`
- `ssh -i tgw-lab-key.pem ec2-user@10.2.3.10`
- `ssh -i tgw-lab-key.pem ec2-user@10.2.4.10`

## Consolidation Notes

These earlier April 4 drafts were superseded by this report and archived:
- `2026-04-04_network-status-report.md`
- `2026-04-04_network-diagnosis-skill-validation.md`
- `2026-04-04_network-flow-check-post-nlb-removal.md`
