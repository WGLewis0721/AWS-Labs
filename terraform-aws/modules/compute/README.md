# compute module

This module owns the EC2 layer, the key pair, the Palo Alto ENIs, and the instance bootstrap behavior.

## What It Creates

- EC2 key pair
- B1 as a three-ENI instance
- standalone ENIs for Palo untrust, trust, and mgmt
- EIP for the Palo untrust ENI
- A1, A2, C1, C2, C3, and D1
- user data for Windows, Linux jump, Palo simulation, and AppGate simulations

## Current Architecture Notes

Important current assumptions:

- `B1` is validated operationally through the mgmt ENI `10.1.3.10`
- `C1`, `C2`, and `C3` are private-only
- `C3` landing-page validation is currently on `443`, not `8443`
- `instance_ami_ids` can override default AMIs for staged deployments

## Golden AMI Support

This module supports the staged deployment flow by allowing AMI overrides:

- defaults come from Amazon-owned AMI data sources
- fresh staged deployments can inject AMI IDs through `instance_ami_ids`
- `artifacts/scripts/deploy.ps1` generates `generated.instance-amis.auto.tfvars.json` to drive that override path

Do not hardcode specific AMI IDs in this module.

## Bootstrap Notes

Current bootstrap behavior is intentionally mixed:

- `A1` installs Chrome
- `A2` is the admin and bootstrap host
- `B1` uses a self-contained Python-based static page bootstrap plus multi-ENI routing setup
- `C1` uses nginx and a self-signed TLS configuration in Terraform user data
- `C2` and `C3` still have a lighter in-instance bootstrap, but the staged deploy flow can normalize Linux web nodes through `A2` using the S3-hosted nginx bundle

Operational implication:

- raw Terraform apply can create the instances
- the staged deploy script is still the preferred convergence path for a clean environment because it also performs the post-deploy Linux normalization

## Outputs

Key outputs:

- `instance_ids`
- `private_ips`
- `public_ips`
- `named_instances`
- `key_pair_name`
- `palo_eni_ids`
- `palo_untrust_eip`
