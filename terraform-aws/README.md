# terraform-aws

This repository contains a Terraform-based AWS Transit Gateway segmentation lab. It is organized as reusable modules plus per-environment roots, but the `dev` environment is the fully built lab described below.

## What this lab is

The lab models a segmented environment with a controlled management entry point, shared inspection tiers, and a customer segment that is intentionally isolated from direct management access.

It builds:

- 4 VPCs with 1 subnet each
- 2 Transit Gateways with separate route tables
- 5 EC2 instances that represent the lab roles
- custom VPC route tables
- custom network ACLs
- custom security groups
- a remote Terraform backend for the `dev` environment

## Topology

```text
                         Internet
                            |
                    +-----------------+
                    | VPC-A CloudHost |
                    | 10.0.0.0/16     |
                    |                 |
                    | A1 Windows      | <- public RDP entry point
                    | A2 Linux        | <- public SSH/admin jump host
                    +--------+--------+
                             |
                           TGW1
                 +-----------+-----------+
                 |                       |
        +--------+--------+     +--------+--------+
        | VPC-B Palo Alto |     | VPC-C AppGate   |
        | 10.1.0.0/16     |     | 10.2.0.0/16     |
        | B1              |     | C1              |
        +--------+--------+     +--------+--------+
                 \                       /
                  \                     /
                           TGW2
                            |
                    +-------+--------+
                    | VPC-D Customer |
                    | 10.3.0.0/16    |
                    | D1             |
                    +----------------+
```

## How it is supposed to work

This lab is designed around bastion-style access, not direct exposure of every workload to the internet.

- Your laptop connects to `A1` over RDP for manual browser checks.
- Your laptop connects to `A2` over SSH for terminal-based administration and validation.
- `A1` and `A2` can reach `B1` and `C1`.
- `B1` and `C1` sit on both transit domains and represent shared service or inspection tiers.
- The validated administrative path to `D1` is through `B1`.
- `VPC-A` does not have a direct allowed path to `VPC-D`.

In other words, the environment is meant to behave like a real segmented network:

- public ingress exists only at the management edge in `VPC-A`
- east-west movement is controlled by route tables, security groups, and NACLs
- the customer segment in `VPC-D` is reachable only through the intended internal path

## Lab components

| Node | VPC | Private IP | Public IP | Purpose |
| --- | --- | --- | --- | --- |
| A1 | VPC-A | `10.0.1.10` | yes, assigned at apply time | Windows bastion for RDP and Chrome-based checks |
| A2 | VPC-A | `10.0.1.20` | yes, assigned at apply time | Linux bastion for SSH and CLI validation |
| B1 | VPC-B | `10.1.1.10` | no | Palo Alto simulation host with SSH and HTTP service |
| C1 | VPC-C | `10.2.1.10` | no | AppGate simulation host with SSH and HTTP service |
| D1 | VPC-D | `10.3.1.10` | no | customer test client used to prove segmentation |

The instance roles are intentionally simple:

- `A1` installs Google Chrome and is used for manual HTTP validation.
- `A2` is the operator jump box.
- `B1` and `C1` each run a lightweight static web service on port `80`.
- `D1` is a Linux test host with no public IP.

## Transit gateways and routing

Two Transit Gateways are used to model segmented connectivity:

- `TGW1` is the management side and connects `VPC-A`, `VPC-B`, and `VPC-C`
- `TGW2` is the customer side and connects `VPC-B`, `VPC-C`, and `VPC-D`

That means:

- `VPC-A` can route to `VPC-B` and `VPC-C`
- `VPC-D` can route to `VPC-B` and `VPC-C`
- `VPC-A` has no route to `VPC-D`

This is the core of the exercise. `B1` and `C1` are the shared middle tiers that attach to both TGWs, while `A` and `D` remain separated from each other.

## Expected connectivity

These are the intended outcomes for the deployed lab:

| Source | Destination | Protocol | Expected result |
| --- | --- | --- | --- |
| A2 | B1 | SSH | allowed |
| A2 | C1 | SSH | allowed |
| A2 | D1 | SSH | blocked |
| A2 | B1 | HTTP | allowed |
| A2 | C1 | HTTP | allowed |
| A2 | D1 | HTTP | blocked |
| A2 | B1/C1 | ICMP | allowed |
| A2 | D1 | ICMP | blocked |
| B1 | D1 | SSH | allowed |
| B1 | D1 | ICMP | allowed |
| D1 | B1 | HTTP | allowed |
| D1 | C1 | HTTP | allowed |
| D1 | A2 | HTTP | blocked |
| A1 Chrome | B1 | HTTP | allowed |
| A1 Chrome | C1 | HTTP | allowed |
| A1 Chrome | D1 | HTTP | blocked |

## Repository structure

The repository keeps reusable components separate from environment roots:

- `modules/network`: VPCs, subnets, Internet Gateway, Transit Gateways, route tables, and NACLs
- `modules/security`: security groups and default SG hardening
- `modules/compute`: EC2 instances, key pair, AMI selection, and user data
- `environments/dev`: the working lab environment
- `environments/staging`: placeholder environment root
- `environments/prod`: placeholder environment root
- `examples/simple-stack`: example module composition

## Backend

The `dev` environment uses a remote backend with these names:

- S3 bucket: `terraform-lab-wgl`
- DynamoDB table: `terraform-lab-db-wgl`
- region: `us-east-1`

The backend config lives in [backend.hcl](C:/Users/Willi/projects/Labs/terraform-aws/environments/dev/backend.hcl) for local use, and the template lives in [backend.hcl.example](C:/Users/Willi/projects/Labs/terraform-aws/environments/dev/backend.hcl.example).

## Prerequisites

Before you deploy or operate the lab, you need:

- Terraform installed locally
- AWS CLI installed and authenticated
- access to the target AWS account in `us-east-1`
- an SSH key pair where the public key is supplied to Terraform as `public_key`
- the matching private key file available locally as `tgw-lab-key.pem`
- an RDP client if you want to use `A1`

For real use, narrow `management_cidrs` to your actual admin source range. The example value of `0.0.0.0/0` is for a disposable lab only.

## Deploying the dev lab

Format the repository first:

```bash
cd terraform-aws
terraform fmt -recursive
```

Create your local variable file:

```bash
cd environments/dev
Copy-Item terraform.tfvars.example terraform.tfvars
```

Update at least these values in `terraform.tfvars`:

- `public_key`
- `management_cidrs`
- `common_tags.Owner`

Then initialize and deploy:

```bash
terraform init -backend-config=backend.hcl
terraform validate
terraform plan
terraform apply
```

## Useful outputs

After `apply`, the environment exposes the values you need most often:

- `a1_windows_public_ip`
- `a2_linux_public_ip`
- `private_ips`
- `public_ips`
- `instance_ids`
- `rdp_password_decrypt_command`
- `test_commands`
- `validation_targets`

Show them with:

```bash
terraform output
terraform output -json
```

## How to access the lab

### A1 Windows bastion

Use `A1` when you want a browser inside the management segment.

1. Get the public IP:

```bash
terraform output -raw a1_windows_public_ip
```

2. Get the Windows Administrator password by running the command emitted by:

```bash
terraform output -raw rdp_password_decrypt_command
```

3. Open an RDP session to the returned `A1` public IP.
4. Launch Chrome on `A1`.
5. Browse to:

- `http://10.1.1.10`
- `http://10.2.1.10`
- `http://10.3.1.10`

Expected behavior:

- `B1` loads
- `C1` loads
- `D1` does not load

### A2 Linux bastion

Use `A2` for SSH, CLI checks, and most day-to-day validation.

Get the public IP and connect:

```bash
terraform output -raw a2_linux_public_ip
ssh -i tgw-lab-key.pem ec2-user@$(terraform output -raw a2_linux_public_ip)
```

If you want to SSH onward from inside `A2`, make sure your key is available there through agent forwarding or by temporarily placing the PEM on the host. Once connected, validate the main paths:

```bash
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@10.1.1.10
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@10.2.1.10
ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@10.3.1.10
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://10.1.1.10
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://10.2.1.10
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" http://10.3.1.10
ping -c 3 10.1.1.10
ping -c 3 10.2.1.10
ping -c 3 10.3.1.10
```

Expected behavior:

- SSH, HTTP, and ping to `B1` succeed
- SSH, HTTP, and ping to `C1` succeed
- SSH, HTTP, and ping to `D1` fail from `A2`

## End-to-end operator model

From your laptop, the intended operational path is:

- laptop -> `A1` over RDP for browser tests
- laptop -> `A2` over SSH for admin tasks
- `A2` -> `B1` and `C1` for shared-service validation
- `B1` -> `D1` for customer-segment validation

This is important: only `A1` and `A2` are expected to be directly reachable from the public internet. `B1`, `C1`, and `D1` are private-only instances by design.

## Validation notes

The initial deployment results are captured in [2026-04-03_initial-deployment.md](C:/Users/Willi/projects/Labs/artifacts/results/2026-04-03_initial-deployment.md).

As of the initial deployment:

- all terminal-verifiable pass and fail cases matched the intended design
- the A1 Chrome checks remain a manual operator step

## Teardown and cost cleanup

Use [teardown.ps1](C:/Users/Willi/projects/Labs/terraform-aws/scripts/teardown.ps1) when you want to remove the lab and stop ongoing AWS charges.

By default, the teardown script removes:

- EC2 instances and their attached root volumes
- VPCs, subnets, route tables, Internet Gateway, security groups, and NACLs
- both Transit Gateways and all TGW attachments
- the remote Terraform backend bucket and DynamoDB lock table

The script intentionally does not remove:

- local repository files
- local `terraform.tfvars`
- local key material such as `tgw-lab-key.pem`
- IAM users, groups, roles, and access keys

Run the full teardown from the repository root:

```powershell
cd terraform-aws
.\scripts\teardown.ps1 -Environment dev -Force
```

If you want to destroy the lab resources but keep the backend state storage:

```powershell
cd terraform-aws
.\scripts\teardown.ps1 -Environment dev -KeepBackend -Force
```

What the script does:

1. initializes Terraform against the configured backend
2. runs `terraform destroy -auto-approve`
3. checks for residual tagged lab resources in AWS
4. deletes the backend S3 bucket and DynamoDB table unless `-KeepBackend` is set

Recommended operator sequence:

1. Make sure no one is actively using `A1` or `A2`.
2. If you want an audit trail, save `terraform output -json` and any screenshots before teardown.
3. Run the teardown script with `-Force`.
4. If you kept the backend, verify you still want to retain state before the next deployment.

## Billing and cost access note

This lab can be torn down entirely from Terraform and AWS CLI, but AWS cost tooling has one extra account-level caveat: Cost Explorer may still need to be enabled in the Billing and Cost Management console before API calls succeed for an IAM user.

If `aws ce get-cost-and-usage` returns `AccessDeniedException` with `User not enabled for cost explorer access`, the IAM policy is not the only dependency. The account-level Cost Explorer feature still needs to be enabled in the Billing console.

Some cost-management features also have account-scope prerequisites. For example, Billing Conductor actions only work from a payer account, so attaching IAM permissions alone does not make those APIs usable from a non-payer account.
