# Network Troubleshooting Skill

Canonical workflow content lives in:
`network-troubleshooting.md`

Use that file for the full workflow.

## Current Defaults

Assume all of the following unless the operator explicitly says the design changed:

- no internal `NLB-B` or `NLB-C`
- direct private-IP validation from `A1` and `A2`
- one public customer-entry load balancer only
- no custom Route 53 resources
- `D1` must remain unreachable from VPC-A

## First Response Order

1. Run the canonical A2 netcheck or its SSM document first.
2. If A2 succeeds and A1 fails, treat it as an A1 browser or certificate problem first.
3. If direct private-IP validation fails, inspect route tables, NACLs, and SGs in that order.
4. Use Reachability Analyzer only after the basic path checks.

## Known Issues

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
- scripts kept flagging NLB failures that no longer mattered.

Root cause:
- troubleshooting logic still assumed the pre-refactor internal NLB model.

Fix:
- switch the default validation path to direct private IPs and keep the public customer-entry load balancer separate from operator-path checks
