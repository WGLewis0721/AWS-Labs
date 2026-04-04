# network module

This module owns the lab networking foundation. It is the source of truth for the segmented topology that the rest of the repo assumes.

## What It Creates

- VPCs A, B, C, and D
- all subnets
- Internet Gateways for VPC-A and VPC-B
- NAT Gateway and EIP in VPC-A
- one route table per subnet
- one NACL per subnet
- TGW1 and TGW2
- TGW route tables
- TGW VPC attachments
- TGW route-table associations
- TGW static routes
- VPC-A flow logs
- ACM material and the public customer-entry load balancer

## Current Architecture Notes

This module now reflects the post-refactor design:

- per-subnet route tables, not per-VPC route tables
- per-subnet NACLs, not per-VPC NACLs
- direct private-IP operator validation from VPC-A
- no internal validation load balancers
- one public customer-entry load balancer only

Compatibility nuance:

- the module still exports `alb_dns_name`
- the output name is retained for compatibility with existing automation

## Most Important Route Behaviors

Critical current behaviors:

- VPC-A routes to VPC-B and VPC-C through `TGW1`
- VPC-A has no direct route to VPC-D
- `lab-rt-b-untrust` must keep return routes to:
  - VPC-A through `TGW1`
  - VPC-C through `TGW1`
  - VPC-D through `TGW2`
- VPC-C subnet route tables must keep `0.0.0.0/0 -> TGW1` for centralized egress

## Most Important NACL Behaviors

Critical rules that support the current working path:

- `nacl-a`
  - ingress `111` tcp `80`
  - ingress `112` tcp `443`
  - ingress `113` tcp `8443`
  - egress `125` tcp `80`
- `nacl-c-dmz`
  - egress `96` tcp `80` to `10.2.2.0/24`
- `nacl-c-portal`
  - direct VPC-A access for `80`, `443`, and `22`

Because NACLs are stateless, edits to this module must always consider the full request and return path, not just the destination subnet.

## Outputs

Key outputs:

- `vpc_ids`
- `subnet_ids`
- `route_table_ids`
- `network_acl_ids`
- `transit_gateway_ids`
- `transit_gateway_route_table_ids`
- `transit_gateway_attachment_ids`
- `nat_gateway_eip`
- `alb_dns_name`

Those outputs are consumed by the environment root and by the security and compute modules.
