# terraform-aws

This repository contains the working Terraform configuration for the TGW segmentation lab. The current steady-state design is the post-refactor architecture plus the Model 2+3 two-table TGW inspection pattern applied on April 7, 2026.

## Current Architecture

The lab models a segmented environment with a public management edge, direct private-IP validation from VPC-A into the shared service tiers, and a customer segment that stays isolated from VPC-A.

Core components:

- 4 VPCs
  - VPC-A `10.0.0.0/16` - management / cloud host
  - VPC-B `10.1.0.0/16` - Palo Alto simulation
  - VPC-C `10.2.0.0/16` - AppGate simulation
  - VPC-D `10.3.0.0/16` - customer segment
- 9 subnets
  - `a`
  - `b_untrust`, `b_trust`, `b_mgmt`
  - `c_dmz`, `c_portal`, `c_gateway`, `c_controller`
  - `d`
- 2 Transit Gateways
  - `TGW1` - management transit domain with Spoke and Firewall route tables
  - `TGW2` - customer transit domain with Spoke and Firewall route tables
- 7 EC2 instances
  - `A1`, `A2`, `B1`, `C1`, `C2`, `C3`, `D1`
- 1 public customer-entry load balancer in VPC-B untrust
- per-subnet route tables and per-subnet NACLs
- centralized internet egress through the NAT Gateway in VPC-A
- VPC-B inspection attachments on both TGWs with appliance mode enabled

## Topology

```text
Internet
  |
  +-- A1 Windows (RDP) in VPC-A
  +-- A2 Linux (SSH) in VPC-A
  |
  +-- Customer-entry load balancer in VPC-B untrust
        |
        +-- B1 untrust ENI 10.1.1.10

TGW1
  |
  +-- Spoke RT: VPC-A and VPC-C; default route to VPC-B
  +-- Firewall RT: VPC-B; return routes to VPC-A and VPC-C
  +-- VPC-A 10.0.0.0/16
  +-- VPC-B 10.1.0.0/16
  |     B1 mgmt:   10.1.3.10
  |     B1 trust:  10.1.2.10
  |     B1 untrust 10.1.1.10
  +-- VPC-C 10.2.0.0/16
        C1 portal:     10.2.2.10
        C2 gateway:    10.2.3.10
        C3 controller: 10.2.4.10

TGW2
  |
  +-- Spoke RT: VPC-C and VPC-D; default route to VPC-B
  +-- Firewall RT: VPC-B; return routes to VPC-B, VPC-C, and VPC-D
  +-- VPC-B 10.1.0.0/16
  +-- VPC-C 10.2.0.0/16
  +-- VPC-D 10.3.0.0/16
        D1 customer: 10.3.1.10
```

## Working Access Model

This is the current operator model. Future docs and prompts should assume this unless the architecture is intentionally changed again.

- Laptop -> `A1` over RDP for browser checks
- Laptop -> `A2` over SSH for CLI and admin checks
- `A1` and `A2` validate VPC-B and VPC-C directly by private IP
- `A1` and `A2` do not have a direct route to VPC-D
- `B1`, `C1`, `C2`, and `C3` use centralized egress through `TGW1 -> VPC-A NAT`
- `B1` and VPC-C nodes participate in both transit domains
- `C1` can initiate SSH and HTTPS to `B1` mgmt and HTTPS to `D1`
- `D1` can initiate HTTPS to `C1`
- `D1` is intentionally isolated from VPC-A
- Model 2+3 TGW route tables force spoke traffic through VPC-B inspection
- inter-VPC traffic reaches destination NACLs/SGs from the VPC-B TGW attachment subnet `10.1.2.0/24`

Important current-state facts:

- Operator validation uses direct private-IP targets. There are no separate internal validation load balancers in the design.
- Route 53 is not used for this lab beyond the AWS-managed default VPC resolver. There are no custom hosted zones or custom Resolver endpoints.
- The output name `alb_dns_name` is kept for compatibility and refers to the public customer-entry load balancer DNS name.
- B1 OS-level `tcpdump` is not proof of TGW transit visibility. TGW uses AWS-managed attachment ENIs in `10.1.2.0/24`.

## Instance Inventory

| Node | Role | Private IP(s) | Public exposure | Notes |
| --- | --- | --- | --- | --- |
| A1 | Windows browser bastion | `10.0.1.10` | public IP | RDP entry point for Chrome-based checks |
| A2 | Linux jump box | `10.0.1.20` | public IP | SSH entry point, bootstrap host, diagnostic host |
| B1 | Palo Alto simulation | `10.1.1.10`, `10.1.2.10`, `10.1.3.10` | EIP on untrust | Operator validation target is the mgmt interface `10.1.3.10` |
| C1 | AppGate portal simulation | `10.2.2.10` | private only | Supports direct HTTP and HTTPS validation from VPC-A |
| C2 | AppGate gateway simulation | `10.2.3.10` | private only | Supports direct HTTPS validation from VPC-A |
| C3 | AppGate controller simulation | `10.2.4.10` | private only | Current validation page is on `443`, not `8443` |
| D1 | Customer host | `10.3.1.10` | private only | Must stay unreachable from VPC-A |

## Expected Connectivity

Healthy state:

| Source | Destination | Protocol | Expected |
| --- | --- | --- | --- |
| Laptop | A1 | RDP | allowed |
| Laptop | A2 | SSH | allowed |
| A1 | `10.1.3.10` | HTTPS | allowed |
| A1 | `10.2.2.10` | HTTP / HTTPS | allowed |
| A1 | `10.2.3.10` | HTTPS | allowed |
| A1 | `10.2.4.10` | HTTPS | allowed |
| A1 | `10.3.1.10` | any | blocked |
| A2 | `10.1.3.10` | SSH / HTTPS / ICMP | allowed |
| A2 | `10.2.2.10` | SSH / HTTP / HTTPS / ICMP | allowed |
| A2 | `10.2.3.10` | SSH / HTTPS / ICMP | allowed |
| A2 | `10.2.4.10` | SSH / HTTPS / ICMP | allowed |
| A2 | `10.3.1.10` | SSH / HTTP / ICMP | blocked |
| C1 | `10.1.3.10` | SSH / HTTPS | allowed |
| C1 | `10.3.1.10` | HTTPS | allowed |
| D1 | `10.2.2.10` | HTTPS | allowed |
| B1 | D1 | SSH / ICMP | allowed |
| Customer-entry LB | B1 untrust | TLS 443 | allowed |

Do not use legacy internal DNS validation paths. Use the direct private-IP targets listed above.

## Preferred Deployment Workflow

Use the staged deployment script from the repository root:

```powershell
.\artifacts\scripts\deploy.ps1 -Environment dev
```

This is the canonical deployment path for a fresh or rebuilt environment. It does more than `terraform apply`.

Deployment phases:

1. Preflight checks
2. Seed S3 assets, IAM, SSM documents, and golden AMIs
3. `terraform init`
4. Network foundation targeted apply
5. Security layer targeted apply
6. Compute layer targeted apply
7. Full convergence apply
8. Two-table TGW pattern verification
9. Post-deploy bootstrap and verification

What the deploy script does:

- verifies AWS CLI auth, Terraform, SSH tooling, and `terraform.tfvars`
- uploads deploy and netcheck assets to `s3://terraform-lab-wgl/`
- creates or updates:
  - `lab-netcheck-a1`
  - `lab-netcheck-a2`
- ensures diagnostic instance profiles exist for `A1` and `A2`
- creates golden AMIs if they do not already exist
- writes `generated.instance-amis.auto.tfvars.json` into `terraform-aws/environments/dev/`
- applies Terraform in phases to reduce blast radius and improve troubleshooting
- verifies Spoke/Firewall TGW route tables and VPC-B appliance mode after full convergence
- copies the key to `A2`
- bootstraps nginx and TLS on the Linux web nodes through `A2` using the S3-hosted RPM bundle
- runs SSM-backed netchecks and stores results in S3

This workflow is the main reason the repo is now more stable and requires less operator back-and-forth.

## Manual Terraform Workflow

Use direct Terraform commands only when you are intentionally working on the modules or reviewing a change set. For full environment builds, prefer `artifacts/scripts/deploy.ps1`.

PowerShell commands:

```powershell
Set-Location .\terraform-aws\environments\dev
terraform --% init -backend-config=backend.hcl
terraform --% plan -out=tfplan -no-color
terraform --% apply tfplan
```

When using raw Terraform:

- always review the destroy set
- treat destroys of `aws_vpc`, `aws_ec2_transit_gateway`, or `aws_ec2_transit_gateway_vpc_attachment` as an immediate stop
- large `aws_network_acl_rule` churn can be expected during NACL refactors and is not a stop condition by itself

## Validation Workflow

### A1 browser checks

RDP to `A1`, open Chrome, and validate:

- `https://10.1.3.10`
- `http://10.2.2.10`
- `https://10.2.2.10`
- `https://10.2.3.10`
- `https://10.2.4.10`

Expected:

- `B1`, `C1`, `C2`, and `C3` load after certificate warnings
- `D1` does not load

### A2 CLI checks

SSH to `A2` and validate:

```bash
ssh -i tgw-lab-key.pem ec2-user@10.1.3.10
ssh -i tgw-lab-key.pem ec2-user@10.2.2.10
ssh -i tgw-lab-key.pem ec2-user@10.2.3.10
ssh -i tgw-lab-key.pem ec2-user@10.2.4.10
curl -sk https://10.1.3.10
curl -s http://10.2.2.10
curl -sk https://10.2.2.10
curl -sk https://10.2.3.10
curl -sk https://10.2.4.10
curl -s --connect-timeout 5 http://10.3.1.10
```

Expected:

- `200` for the VPC-B and VPC-C targets
- failure for `D1`

### East-west service checks

From `C1` (SSH: `A2 -> 10.2.2.10`), validate:

```bash
timeout 5 bash -lc '</dev/tcp/10.1.3.10/22' >/dev/null 2>&1 && echo "B1 mgmt SSH reachable"
curl -sk https://10.1.3.10
curl -sk https://10.3.1.10
```

Expected:

- `B1` mgmt SSH port reachable from `C1`
- `200` from `B1` mgmt HTTPS
- `200` from `D1` HTTPS

From `D1` if you have an interactive shell, validate:

```bash
curl -sk https://10.2.2.10
```

Expected:

- `200` from `C1` HTTPS
- Reachability Analyzer can still report a false negative on multi-hop TGW inspection paths because it does not model TGW source-IP substitution to the attachment subnet. Prefer actual curl results plus TGW route table, NACL, SG, and appliance-mode checks.

### SSM netchecks

Canonical netcheck scripts live under `artifacts/scripts/`:

- `netcheck-a1.ps1`
- `netcheck.sh`
- `ssm-netcheck-a1.yml`
- `ssm-netcheck-a2.yml`

Canonical SSM documents:

- `lab-netcheck-a1`
- `lab-netcheck-a2`

The deploy script uploads the script payloads to:

- `s3://terraform-lab-wgl/ssm/netcheck/a1/`
- `s3://terraform-lab-wgl/ssm/netcheck/a2/`
- `s3://terraform-lab-wgl/ssm/netcheck/docs/`

The deploy script also stores SSM command output under:

- `s3://terraform-lab-wgl/deploy/netchecks/<timestamp>/a1/`
- `s3://terraform-lab-wgl/deploy/netchecks/<timestamp>/a2/`

## Current Nuances And Lessons Learned

These items are codified in Terraform and should remain true unless the architecture is intentionally changed.

### 1. Model 2+3 uses Spoke and Firewall TGW route tables

Each TGW uses two active inspection route tables:

- Spoke RT: associated with spoke VPCs and has `0.0.0.0/0 -> VPC-B`
- Firewall RT: associated with VPC-B and has specific routes back to the spokes

TGW1 Spoke RT is associated with VPC-A and VPC-C. TGW1 Firewall RT is associated with VPC-B.

TGW2 Spoke RT is associated with VPC-C and VPC-D. TGW2 Firewall RT is associated with VPC-B.

VPC-B attachments on both TGWs must keep appliance mode enabled.

### 2. Model 2+3 changes the source CIDR seen by destination controls

After traffic is forced through the inspection path, destination NACLs and SGs must allow the VPC-B TGW attachment subnet:

- `10.1.2.0/24`

This is why the C1/C2/C3 security groups include HTTPS ingress from `10.1.2.0/24` and the C-side NACLs include additional rules for that source.

### 3. Per-subnet route tables and NACLs are required

The stable design is per-subnet, not per-VPC. Future changes should preserve:

- one route table per subnet
- one NACL per subnet
- explicit TGW associations
- explicit TGW route entries

### 4. `lab-rt-b-untrust` needs explicit return routes

The B1 untrust subnet must keep:

- `10.0.0.0/16 -> TGW1`
- `10.2.0.0/16 -> TGW1`
- `10.3.0.0/16 -> TGW2`
- `0.0.0.0/0 -> IGW`

Without those return routes, ping may work while TCP fails.

### 5. VPC-C route tables need default egress through `TGW1` and a VPC-D route through `TGW2`

The VPC-C subnets use centralized egress:

- `0.0.0.0/0 -> TGW1 -> VPC-A NAT`
- `10.3.0.0/16 -> TGW2`

That is required for package installation, updates, and bootstrap resilience.

### 6. `nacl-a` needs the service-port return path

Because `A2` and the TGW attachment share the VPC-A subnet, `nacl-a` must retain:

- ingress `111` tcp `80` from `10.0.0.0/16`
- ingress `112` tcp `443` from `10.0.0.0/16`
- ingress `113` tcp `8443` from `10.0.0.0/16`
- egress `125` tcp `80` to `10.2.0.0/16`

### 7. `nacl-c-dmz` needs Model 2+3 transit rules

The VPC-C DMZ subnet must keep at least:

- egress `96` tcp `80` to `10.2.2.0/24`
- ingress `99` tcp `80` from `10.1.2.0/24`
- ingress `100` tcp `443` from `10.1.2.0/24`
- egress `110` tcp `1024-65535` to `10.1.2.0/24`

Those rules are part of the inspected A2/A1 -> C1 path.

### 8. C1 bootstrap is more sensitive than the other Linux nodes

`C1` needs full nginx configuration with TLS, not just a placeholder listener.

Required behavior:

- stop any placeholder server on `80` and `443`
- install nginx and openssl
- generate `/etc/nginx/ssl/selfsigned.crt` and `selfsigned.key`
- write `/etc/nginx/conf.d/ssl.conf`
- enable and restart nginx

### 9. `C1` and `D1` keep `source_dest_check = false`

The validated east-west model requires:

- `C1` source/dest check disabled
- `D1` source/dest check disabled

If those drift back to `true`, Reachability Analyzer and cross-VPC forwarding behavior will regress.

### 10. The deploy script is the canonical convergence workflow

The repo is now designed around:

- golden AMI reuse
- S3-hosted bootstrap assets
- A2-driven Linux post-bootstrap
- SSM netchecks

Do not assume `terraform apply` alone is the full deployment process.

## Outputs You Will Use Most

Important outputs from `terraform output`:

- `a1_windows_public_ip`
- `a2_linux_public_ip`
- `alb_dns_name`
- `nat_gateway_eip`
- `private_ips`
- `instance_ids`
- `rdp_password_decrypt_command`
- `test_commands`
- `validation_targets`

`alb_dns_name` is the public customer-entry DNS name. The output name remains `alb_dns_name` for compatibility.

## Repository Structure

Main areas:

- `modules/network` - VPCs, subnets, route tables, TGWs, NACLs, NAT, customer-entry LB
- `modules/security` - security groups
- `modules/compute` - EC2 instances, ENIs, key pair, user data, AMI overrides
- `environments/dev` - working lab environment
- `artifacts/scripts` - canonical deployment, teardown, bootstrap, and netcheck scripts
- `artifacts/skills` - project-specific operator guidance
- `artifacts/prompts` - Copilot session instructions and handoff prompts
- `artifacts/results` - human-readable reports and raw validation output

## Teardown

Use the canonical teardown entrypoint from the repository root:

```powershell
.\artifacts\scripts\teardown.ps1 -Environment dev -Force
```

Keep the backend if needed:

```powershell
.\artifacts\scripts\teardown.ps1 -Environment dev -KeepBackend -Force
```

The teardown script is the cost-control path. Use it when you are finished with the lab.
