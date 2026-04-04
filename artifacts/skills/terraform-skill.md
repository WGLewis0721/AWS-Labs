# Skill: Terraform - AWS Infrastructure

## Purpose

This skill defines the current Terraform rules for the TGW segmentation lab. It is written against the post-refactor architecture that is actually running today.

Use this skill when:

- reading or changing the Terraform modules
- reviewing a plan
- deciding whether a live AWS fix still needs to be codified
- preparing a fresh deployment workflow

## Current Steady-State Architecture

Assume this architecture unless the user explicitly says otherwise:

- no internal validation load balancers
- direct private-IP operator validation from VPC-A
- one public customer-entry load balancer in VPC-B untrust
- centralized egress through the NAT Gateway in VPC-A
- one route table and one NACL per subnet
- golden AMI reuse is part of the preferred deployment workflow

Current operator validation targets:

- `B1` mgmt: `10.1.3.10`
- `C1` portal: `10.2.2.10`
- `C2` gateway: `10.2.3.10`
- `C3` controller: `10.2.4.10`
- `D1` customer: `10.3.1.10` must remain unreachable from VPC-A

## Preferred Deployment Workflow

For a full environment build, prefer:

```powershell
.\artifacts\scripts\deploy.ps1 -Environment dev
```

Do not treat raw `terraform apply` as the entire deployment workflow for a fresh environment. The deploy script also:

- seeds S3 bootstrap assets
- creates or reuses golden AMIs
- writes `generated.instance-amis.auto.tfvars.json`
- phases the Terraform apply by module
- attaches SSM-capable instance profiles
- bootstraps nginx on Linux nodes through `A2`
- runs SSM netchecks

Use raw Terraform when the task is specifically about module development, plan review, or controlled manual apply.

## Provider And Version Expectations

Current expectations:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}
```

Before using a new argument or resource behavior, verify current provider docs or changelog if the topic is version-sensitive.

## Mandatory Pre-Apply Steps

PowerShell form:

```powershell
terraform fmt -check -recursive
terraform validate
terraform --% plan -out=tfplan -no-color
```

If formatting fails:

```powershell
terraform fmt -recursive
```

Plan review rules:

- `+` is normal for new resources
- `~` needs review
- `-` requires explanation
- `-/+` means replacement and must be treated as downtime risk

Hard stop resources:

- `aws_vpc`
- `aws_ec2_transit_gateway`
- `aws_ec2_transit_gateway_vpc_attachment`

Those must not appear in the destroy or replace set without explicit operator review.

## Destroy Count Guidance

Raw destroy count is not enough by itself.

Known safe refactor profile from this lab:

- about `101` `aws_network_acl_rule`
- about `11` `aws_route`
- about `6` `aws_ec2_transit_gateway_route`
- a small number of SG, subnet, instance, NACL, and route-table replacements

That `131`-destroy refactor was expected and safe because the destroyed resources were the old per-VPC network objects, not the core VPC or TGW primitives.

## Resource Model

Current subnet layout:

- `a` -> `10.0.1.0/24`
- `b_untrust` -> `10.1.1.0/24`
- `b_trust` -> `10.1.2.0/24`
- `b_mgmt` -> `10.1.3.0/24`
- `c_dmz` -> `10.2.1.0/24`
- `c_portal` -> `10.2.2.0/24`
- `c_gateway` -> `10.2.3.0/24`
- `c_controller` -> `10.2.4.0/24`
- `d` -> `10.3.1.0/24`

Naming patterns still matter, but do not rely on the old one-subnet-per-VPC assumption.

## AMI Rules

Default AMI selection still uses data sources and filters. Do not hardcode AWS AMI IDs into the module.

Current nuance:

- the environment can override AMIs through `instance_ami_ids`
- the staged deploy script generates `generated.instance-amis.auto.tfvars.json`
- that file is local/generated state and should not be hand-edited unless the task explicitly requires it

## Security Rules

Public ingress should remain limited to the management edge:

- `A1` RDP `3389`
- `A2` SSH `22`
- customer-entry load balancer `80/443`

Everything else should be scoped to internal CIDRs.

The lab no longer depends on internal load balancers for B or C. If a change reintroduces them implicitly, call that out as an architecture change, not a routine fix.

## Route Table Completeness Rule

Every subnet route table must include all required return paths for the flows it participates in.

Critical current routes:

- `lab-rt-b-untrust`
  - `10.0.0.0/16 -> TGW1`
  - `10.2.0.0/16 -> TGW1`
  - `10.3.0.0/16 -> TGW2`
  - `0.0.0.0/0 -> IGW`
- VPC-C subnet route tables
  - `0.0.0.0/0 -> TGW1`

If those regress, connectivity will look asymmetric and confusing.

## NACL Completeness Rule

NACLs are stateless. Every allowed TCP path needs:

- request-side outbound
- destination-side inbound
- destination-side outbound ephemeral
- source-side inbound ephemeral

For `A2 -> C1`, three NACLs matter:

1. `nacl-a`
2. `nacl-c-dmz`
3. `nacl-c-portal`

Missing any one of them breaks the flow.

Critical current rules:

- `nacl-a`
  - ingress `111` tcp `80` from `10.0.0.0/16`
  - ingress `112` tcp `443` from `10.0.0.0/16`
  - ingress `113` tcp `8443` from `10.0.0.0/16`
  - egress `125` tcp `80` to `10.2.0.0/16`
- `nacl-c-dmz`
  - egress `96` tcp `80` to `10.2.2.0/24`
- `nacl-c-portal`
  - direct-access rules from VPC-A on `80`, `443`, and `22`

## TGW Rules

These must remain explicit:

```hcl
default_route_table_association = "disable"
default_route_table_propagation = "disable"
```

And on attachments:

```hcl
transit_gateway_default_route_table_association = false
transit_gateway_default_route_table_propagation = false
```

Do not allow the lab to drift back to TGW defaults.

## Linux Web Stack Rules

`C1` is nginx-based in Terraform and requires:

1. stop placeholder listeners on `80` and `443`
2. install `nginx`, `openssl`, and `psmisc`
3. generate the self-signed cert under `/etc/nginx/ssl`
4. write `ssl.conf`
5. enable and restart nginx

Current deployment nuance:

- the staged deploy script also pushes an S3-hosted RPM bundle and can normalize the Linux nodes from `A2`
- do not remove that post-deploy bootstrap path unless the replacement is equally deterministic

## Output Expectations

Useful outputs:

- `a1_windows_public_ip`
- `a2_linux_public_ip`
- `alb_dns_name`
- `nat_gateway_eip`
- `private_ips`
- `instance_ids`
- `rdp_password_decrypt_command`
- `test_commands`
- `validation_targets`

Compatibility note:

- `alb_dns_name` is still the output name for compatibility and refers to the public customer-entry load balancer DNS name

## Common Errors

| Error | Cause | Fix |
| --- | --- | --- |
| TGW route looks right but TCP still fails | one subnet route table is missing the return path | inspect the specific subnet route table, not just the VPC |
| SG looks right but HTTPS still times out | one NACL hop is missing | check `nacl-a`, `nacl-c-dmz`, and destination subnet NACL |
| nginx not serving on C1 | placeholder server still bound or nginx incomplete | check `cloud-init`, kill listeners, rebuild nginx config |
| A1/A2 validation uses legacy internal DNS names | stale docs or stale prompts | switch to direct private-IP checks |
| Fresh deploy takes too long or drifts | not using golden AMIs and staged deploy flow | use `artifacts/scripts/deploy.ps1` |
