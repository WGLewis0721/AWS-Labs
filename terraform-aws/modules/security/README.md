# security module

This module owns the security groups for the lab and hardens the default security group in each VPC.

## What It Creates

- cleared default security groups for all VPCs
- `A1` Windows SG
- `A2` Linux SG
- Palo untrust, trust, and mgmt SGs
- `C1`, `C2`, and `C3` SGs
- `D1` SG

## Current Security Model

Public ingress is intentionally limited to:

- `A1` RDP
- `A2` SSH
- customer-entry load balancer traffic into VPC-B

Operator-path private validation from VPC-A depends on these SG expectations:

- `B1` mgmt allows `22` and `443` from `10.0.0.0/16`
- `C1` allows `22`, `80`, and `443` from `10.0.0.0/16`
- `C2` allows `22` and `443` from `10.0.0.0/16`
- `C3` allows `22` and `443` from `10.0.0.0/16`
- `D1` must not be reachable from VPC-A

## Current Architecture Notes

- internal validation load balancers are not part of the current design
- do not preserve old SG rules that only existed to support those removed internal load balancers
- the security groups are only one part of the path; they must remain aligned with the per-subnet NACLs in the network module

## Management CIDRs

`A1` and `A2` public access is driven by `management_cidrs`.

Use a narrow operator CIDR in real use. `0.0.0.0/0` is only acceptable for disposable lab work.
