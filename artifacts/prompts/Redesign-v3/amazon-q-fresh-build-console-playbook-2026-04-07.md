# Amazon Q Fresh Build Console Playbook - Captured 2026-04-07

## Review Note

This file captures Amazon Q guidance for later review. It is lightly formatted for readability, but it is not treated as the authoritative current repo architecture.

Review flags before using this operationally:

- The repo's preferred fresh deployment workflow is `artifacts/scripts/deploy.ps1 -Environment dev`, not a manual console build.
- Compare all NACL, security group, and route-table details against the current Terraform before applying them.
- The current acceptance checks are direct HTTP/HTTPS private-IP checks from VPC-A plus D1 isolation. C-host SSH from A2 is diagnostic only, not an acceptance target.
- B1 OS-level `tcpdump` is not a valid proof of TGW transit visibility because TGW uses AWS-managed attachment ENIs.
- Phase 10 references a "previous playbook"; the current repo's Model 2+3 Terraform and docs should be the source of truth for that step.

## Overview Of Build Order

VPCs -> Subnets -> IGW -> NAT GW -> Route Tables -> NACLs -> Security Groups -> TGWs -> TGW Attachments -> TGW Route Tables -> EC2 Instances -> TGW Routing -> Verify

## Phase 1 - VPCs

VPC -> Your VPCs -> Create VPC. Select "VPC only", not "VPC and more".

| Name | IPv4 CIDR |
| --- | --- |
| `lab-vpc-a` | `10.0.0.0/16` |
| `lab-vpc-b` | `10.1.0.0/16` |
| `lab-vpc-c` | `10.2.0.0/16` |
| `lab-vpc-d` | `10.3.0.0/16` |

Tag each with `Project = <your project name>`.

## Phase 2 - Subnets

VPC -> Subnets -> Create subnet. Select the correct VPC for each group.

VPC-A:

| Name | VPC | AZ | CIDR |
| --- | --- | --- | --- |
| `lab-subnet-a` | `vpc-a` | `us-east-1a` | `10.0.1.0/24` |

VPC-B:

| Name | VPC | AZ | CIDR |
| --- | --- | --- | --- |
| `lab-subnet-b-untrust` | `vpc-b` | `us-east-1a` | `10.1.1.0/24` |
| `lab-subnet-b-trust` | `vpc-b` | `us-east-1a` | `10.1.2.0/24` |
| `lab-subnet-b-mgmt` | `vpc-b` | `us-east-1a` | `10.1.3.0/24` |

VPC-C:

| Name | VPC | AZ | CIDR |
| --- | --- | --- | --- |
| `lab-subnet-c-dmz` | `vpc-c` | `us-east-1a` | `10.2.1.0/24` |
| `lab-subnet-c-portal` | `vpc-c` | `us-east-1a` | `10.2.2.0/24` |
| `lab-subnet-c-gateway` | `vpc-c` | `us-east-1a` | `10.2.3.0/24` |
| `lab-subnet-c-controller` | `vpc-c` | `us-east-1a` | `10.2.4.0/24` |

VPC-D:

| Name | VPC | AZ | CIDR |
| --- | --- | --- | --- |
| `lab-subnet-d` | `vpc-d` | `us-east-1a` | `10.3.1.0/24` |

## Phase 3 - Internet Gateways

VPC -> Internet Gateways -> Create -> Attach to VPC.

| Name | Attach to |
| --- | --- |
| `lab-igw-a` | `vpc-a` |
| `lab-igw-b` | `vpc-b` |

VPC-C and VPC-D get no IGW. They egress through TGW -> VPC-A NAT.

## Phase 4 - Elastic IP And NAT Gateway

VPC -> Elastic IPs -> Allocate. Allocate one EIP and tag it `lab-eip-nat`.

VPC -> NAT Gateways -> Create:

- Name: `lab-nat-gw`
- Subnet: `lab-subnet-a`
- Connectivity: Public
- Elastic IP: the NAT EIP just allocated

Wait for the NAT gateway to show `Available` before continuing.

Also allocate a second EIP for the B1 Palo untrust interface and tag it `lab-eip-palo-untrust`. Attach it later.

## Phase 5 - Route Tables

VPC -> Route Tables -> Create route table.

Create one per subnet and name it to match the subnet. Then for each route table:

- Associate it to its subnet: Subnet associations tab -> Edit -> check the subnet.
- Add routes as listed below.

### `lab-rt-a` - VPC-A

| Destination | Target |
| --- | --- |
| `10.0.0.0/16` | local |
| `10.1.0.0/16` | TGW1, add after TGW created |
| `10.2.0.0/16` | TGW1, add after TGW created |
| `0.0.0.0/0` | `lab-igw-a` |

Do not add a route to `10.3.0.0/16` in VPC-A. D1 must remain unreachable from VPC-A.

### `lab-rt-b-untrust` - VPC-B Untrust Subnet

| Destination | Target |
| --- | --- |
| `10.1.0.0/16` | local |
| `10.0.0.0/16` | TGW1, add after TGW created |
| `10.2.0.0/16` | TGW1, add after TGW created |
| `10.3.0.0/16` | TGW2, add after TGW created |
| `0.0.0.0/0` | `lab-igw-b` |

### `lab-rt-b-trust` - VPC-B Trust Subnet

| Destination | Target |
| --- | --- |
| `10.1.0.0/16` | local |
| `10.0.0.0/16` | TGW1, add after TGW created |
| `10.2.0.0/16` | TGW1, add after TGW created |
| `10.3.0.0/16` | TGW2, add after TGW created |
| `0.0.0.0/0` | TGW1, add after TGW created |

### `lab-rt-b-mgmt` - VPC-B Management Subnet

| Destination | Target |
| --- | --- |
| `10.1.0.0/16` | local |
| `0.0.0.0/0` | `lab-igw-b` |

### VPC-C Route Tables

Applies to `lab-rt-c-dmz`, `lab-rt-c-portal`, `lab-rt-c-gateway`, and `lab-rt-c-controller`.

| Destination | Target |
| --- | --- |
| `10.2.0.0/16` | local |
| `10.0.0.0/16` | TGW1, add after TGW created |
| `10.1.0.0/16` | TGW1, add after TGW created |
| `10.3.0.0/16` | TGW2, add after TGW created |
| `0.0.0.0/0` | TGW1, add after TGW created |

### `lab-rt-d` - VPC-D

| Destination | Target |
| --- | --- |
| `10.3.0.0/16` | local |
| `10.1.0.0/16` | TGW2, add after TGW created |
| `10.2.0.0/16` | TGW2, add after TGW created |
| `0.0.0.0/0` | TGW2, add after TGW created |

Come back to fill in the TGW targets after Phase 7.

## Phase 6 - NACLs

VPC -> Network ACLs -> Create network ACL.

Create one per subnet, associate it to its subnet, then add rules. The default NACL allows everything, so replace it with explicit rules.

### `nacl-a` - `subnet-a`

Inbound:

| Rule | Protocol | Port | Source | Action |
| --- | --- | --- | --- | --- |
| `90` | TCP | `22` | `your-ip/32` | Allow |
| `100` | TCP | `3389` | `your-ip/32` | Allow |
| `111` | TCP | `80` | `10.0.0.0/16` | Allow |
| `112` | TCP | `443` | `10.0.0.0/16` | Allow |
| `113` | TCP | `8443` | `10.0.0.0/16` | Allow |
| `120` | TCP | `1024-65535` | `0.0.0.0/0` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

Outbound:

| Rule | Protocol | Port | Destination | Action |
| --- | --- | --- | --- | --- |
| `100` | TCP | `80` | `0.0.0.0/0` | Allow |
| `110` | TCP | `443` | `0.0.0.0/0` | Allow |
| `119` | TCP | `22` | `10.0.0.0/8` | Allow |
| `120` | TCP | `1024-65535` | `0.0.0.0/0` | Allow |
| `125` | TCP | `80` | `10.2.0.0/16` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

### `nacl-b-untrust` - `subnet-b-untrust`

Inbound:

| Rule | Protocol | Port | Source | Action |
| --- | --- | --- | --- | --- |
| `100` | TCP | `443` | `0.0.0.0/0` | Allow |
| `110` | TCP | `80` | `0.0.0.0/0` | Allow |
| `120` | TCP | `1024-65535` | `10.0.0.0/16` | Allow |
| `130` | TCP | `1024-65535` | `10.3.0.0/16` | Allow |
| `140` | TCP | `1024-65535` | `0.0.0.0/0` | Allow |
| `150` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

Outbound:

| Rule | Protocol | Port | Destination | Action |
| --- | --- | --- | --- | --- |
| `100` | TCP | `1024-65535` | `0.0.0.0/0` | Allow |
| `110` | TCP | `443` | `10.1.2.0/24` | Allow |
| `120` | TCP | `80` | `10.0.0.0/16` | Allow |
| `121` | TCP | `443` | `10.0.0.0/16` | Allow |
| `130` | TCP | `80` | `10.3.0.0/16` | Allow |
| `131` | TCP | `443` | `10.3.0.0/16` | Allow |
| `140` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

### `nacl-b-trust` - `subnet-b-trust`

This is the TGW attachment subnet. All transit flows through here.

Inbound:

| Rule | Protocol | Port | Source | Action |
| --- | --- | --- | --- | --- |
| `85` | TCP | `22` | `10.2.0.0/16` | Allow |
| `86` | TCP | `443` | `10.2.0.0/16` | Allow |
| `90` | TCP | `22` | `10.0.0.0/16` | Allow |
| `91` | TCP | `443` | `10.0.0.0/16` | Allow |
| `92` | TCP | `80` | `10.0.0.0/16` | Allow |
| `100` | TCP | `1024-65535` | `10.1.1.0/24` | Allow |
| `101` | TCP | `1024-65535` | `10.1.3.0/24` | Allow |
| `110` | TCP | `1024-65535` | `10.2.0.0/16` | Allow |
| `120` | TCP | `1024-65535` | `10.0.0.0/16` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

Outbound:

| Rule | Protocol | Port | Destination | Action |
| --- | --- | --- | --- | --- |
| `90` | TCP | `22` | `10.1.3.0/24` | Allow |
| `91` | TCP | `443` | `10.1.3.0/24` | Allow |
| `100` | TCP | `443` | `10.2.0.0/16` | Allow |
| `101` | TCP | `80` | `10.2.0.0/16` | Allow |
| `110` | TCP | `1024-65535` | `10.1.1.0/24` | Allow |
| `120` | TCP | `1024-65535` | `10.0.0.0/16` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

### `nacl-b-mgmt` - `subnet-b-mgmt`

Inbound:

| Rule | Protocol | Port | Source | Action |
| --- | --- | --- | --- | --- |
| `90` | TCP | `22` | `10.0.0.0/16` | Allow |
| `91` | TCP | `443` | `10.0.0.0/16` | Allow |
| `100` | TCP | `1024-65535` | `0.0.0.0/0` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

Outbound:

| Rule | Protocol | Port | Destination | Action |
| --- | --- | --- | --- | --- |
| `90` | TCP | `22` | `10.0.0.0/16` | Allow |
| `100` | TCP | `443` | `0.0.0.0/0` | Allow |
| `110` | TCP | `80` | `0.0.0.0/0` | Allow |
| `120` | TCP | `1024-65535` | `0.0.0.0/0` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

### `nacl-c-dmz` - `subnet-c-dmz`

Inbound:

| Rule | Protocol | Port | Source | Action |
| --- | --- | --- | --- | --- |
| `99` | TCP | `80` | `10.1.2.0/24` | Allow |
| `100` | TCP | `443` | `10.1.2.0/24` | Allow |
| `110` | TCP | `443` | `10.0.0.0/16` | Allow |
| `111` | TCP | `8443` | `10.0.0.0/16` | Allow |
| `112` | TCP | `22` | `10.0.0.0/16` | Allow |
| `113` | TCP | `1024-65535` | `10.2.0.0/16` | Allow |
| `114` | TCP | `1024-65535` | `10.3.0.0/16` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

Outbound:

| Rule | Protocol | Port | Destination | Action |
| --- | --- | --- | --- | --- |
| `95` | TCP | `22` | `10.2.2.0/24` | Allow |
| `96` | TCP | `80` | `10.2.2.0/24` | Allow |
| `100` | TCP | `443` | `10.2.2.0/24` | Allow |
| `101` | TCP | `22` | `10.2.3.0/24` | Allow |
| `102` | TCP | `443` | `10.2.3.0/24` | Allow |
| `103` | TCP | `22` | `10.2.4.0/24` | Allow |
| `104` | TCP | `443` | `10.2.4.0/24` | Allow |
| `107` | TCP | `443` | `10.3.0.0/16` | Allow |
| `110` | TCP | `1024-65535` | `10.1.2.0/24` | Allow |
| `120` | TCP | `1024-65535` | `10.0.0.0/16` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

### `nacl-c-portal` - `subnet-c-portal`

Inbound:

| Rule | Protocol | Port | Source | Action |
| --- | --- | --- | --- | --- |
| `85` | TCP | `443` | `10.3.0.0/16` | Allow |
| `90` | TCP | `80` | `10.0.0.0/16` | Allow |
| `91` | TCP | `443` | `10.0.0.0/16` | Allow |
| `92` | TCP | `22` | `10.0.0.0/16` | Allow |
| `93` | TCP | `80` | `10.1.2.0/24` | Allow |
| `94` | TCP | `443` | `10.1.2.0/24` | Allow |
| `120` | TCP | `1024-65535` | `0.0.0.0/0` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

Outbound:

| Rule | Protocol | Port | Destination | Action |
| --- | --- | --- | --- | --- |
| `85` | TCP | `443` | `10.3.0.0/16` | Allow |
| `87` | TCP | `22` | `10.1.3.0/24` | Allow |
| `88` | TCP | `443` | `10.1.3.0/24` | Allow |
| `89` | TCP | `1024-65535` | `10.1.2.0/24` | Allow |
| `90` | TCP | `1024-65535` | `10.0.0.0/16` | Allow |
| `120` | TCP | `443` | `0.0.0.0/0` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

### `nacl-c-gateway` And `nacl-c-controller`

Use the same pattern as `nacl-c-portal`, but adjust the port ranges to match C2 (`443`, `444`) and C3 (`443`, `444`, `8443`).

The key rule to include in both is ingress from `10.1.2.0/24` on `443` and egress ephemeral `1024-65535` back to `10.1.2.0/24`.

### `nacl-d` - `subnet-d`

Inbound:

| Rule | Protocol | Port | Source | Action |
| --- | --- | --- | --- | --- |
| `100` | TCP | `80` | `0.0.0.0/0` | Allow |
| `110` | TCP | `443` | `0.0.0.0/0` | Allow |
| `115` | TCP | `1024-65535` | `10.2.0.0/16` | Allow |
| `120` | TCP | `1024-65535` | `0.0.0.0/0` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

Outbound:

| Rule | Protocol | Port | Destination | Action |
| --- | --- | --- | --- | --- |
| `100` | TCP | `80` | `0.0.0.0/0` | Allow |
| `101` | TCP | `443` | `0.0.0.0/0` | Allow |
| `110` | TCP | `1024-65535` | `0.0.0.0/0` | Allow |
| `130` | ICMP | all | `10.0.0.0/8` | Allow |
| `32767` | All | all | `0.0.0.0/0` | Deny |

## Phase 7 - Security Groups

EC2 -> Security Groups -> Create security group.

`lab-sg-a-linux` in VPC-A for A2:

- Inbound: SSH `22` from `your-ip/32`
- Outbound: all traffic to `0.0.0.0/0`

`lab-sg-a-windows` in VPC-A for A1:

- Inbound: RDP `3389` from `your-ip/32`
- Outbound: all traffic to `0.0.0.0/0`

`lab-sg-palo-untrust` in VPC-B:

- Inbound: TCP `443` from `0.0.0.0/0`, TCP `80` from `0.0.0.0/0`
- Outbound: all traffic to `0.0.0.0/0`

`lab-sg-palo-trust` in VPC-B:

- Inbound: all traffic from `10.0.0.0/16`
- Inbound: all traffic from `10.2.0.0/16`
- Inbound: TCP `443` from `10.1.2.0/24`
- Outbound: all traffic to `0.0.0.0/0`

`lab-sg-palo-mgmt` in VPC-B:

- Inbound: SSH `22` from `10.0.0.0/16`
- Inbound: TCP `443` from `10.0.0.0/16`
- Outbound: all traffic to `0.0.0.0/0`

`lab-sg-c1-portal` in VPC-C:

- Inbound: TCP `80` from `10.0.0.0/16`
- Inbound: TCP `443` from `10.0.0.0/16`
- Inbound: TCP `22` from `10.0.0.0/16`
- Inbound: TCP `443` from `10.1.2.0/24`
- Inbound: TCP `443` from `10.3.0.0/16`
- Outbound: all traffic to `0.0.0.0/0`

`lab-sg-c2-gateway` in VPC-C:

- Inbound: TCP `443` from `10.0.0.0/16`
- Inbound: TCP `22` from `10.0.0.0/16`
- Inbound: TCP `443` from `10.2.2.0/24`
- Inbound: TCP `443` from `10.1.2.0/24`
- Outbound: all traffic to `0.0.0.0/0`

`lab-sg-c3-controller` in VPC-C:

- Inbound: TCP `443` from `10.0.0.0/16`
- Inbound: TCP `8443` from `10.0.0.0/16`
- Inbound: TCP `22` from `10.0.0.0/16`
- Inbound: TCP `443` from `10.1.2.0/24`
- Outbound: all traffic to `0.0.0.0/0`

`lab-sg-vpc-d` in VPC-D for D1:

- Inbound: TCP `22` from `10.0.0.0/16`, ICMP from `10.0.0.0/8`
- Outbound: all traffic to `0.0.0.0/0`

## Phase 8 - Transit Gateways

VPC -> Transit Gateways -> Create transit gateway.

| Setting | TGW1 | TGW2 |
| --- | --- | --- |
| Name | `lab-tgw1-mgmt` | `lab-tgw2-customer` |
| ASN | `64512` | `64513` |
| Default RT association | Disabled | Disabled |
| Default RT propagation | Disabled | Disabled |
| DNS support | Enabled | Enabled |
| VPN ECMP | Enabled | Enabled |

Wait for both to show `Available` before continuing.

## Phase 9 - TGW Attachments

VPC -> Transit Gateway Attachments -> Create transit gateway attachment.

Settings:

- Attachment type: VPC
- DNS support: Enable
- IPv6 support: Disable
- Appliance mode: Enable only for VPC-B attachments. Disable for all others.

| Name | TGW | VPC | Subnet | Appliance Mode |
| --- | --- | --- | --- | --- |
| `tgw1-attach-vpc-a` | TGW1 | `vpc-a` | `subnet-a` | Disable |
| `tgw1-attach-vpc-b` | TGW1 | `vpc-b` | `subnet-b-trust` | Enable |
| `tgw1-attach-vpc-c` | TGW1 | `vpc-c` | `subnet-c-dmz` | Disable |
| `tgw2-attach-vpc-b` | TGW2 | `vpc-b` | `subnet-b-trust` | Enable |
| `tgw2-attach-vpc-c` | TGW2 | `vpc-c` | `subnet-c-dmz` | Disable |
| `tgw2-attach-vpc-d` | TGW2 | `vpc-d` | `subnet-d` | Disable |

Wait for all six to show `Available`.

Go back to Phase 5 and fill in all TGW targets in the route tables.

## Phase 10 - TGW Route Tables, Routes, And Associations

Follow the previous playbook exactly, phases 1 through 4. Create the four new route tables, populate routes, then do the association cutover.

Because this is a fresh environment, the "old RT" is the default RT that was auto-created when each TGW was created. Disassociate from that.

## Phase 11 - Key Pair

EC2 -> Key Pairs -> Create key pair.

- Name: `tgw-lab-key`
- Type: RSA
- Format: `.pem`

Download and save it. It is needed to SCP files to A2 and SSH from A2 to other instances.

## Phase 12 - EC2 Instances

Launch order: A2 first, then B1, then C1/C2/C3, then D1, then A1 last.

### A2 - Linux Jump Host

- AMI: Amazon Linux 2023
- Type: `t3.micro`
- VPC: `vpc-a`, `subnet-a`
- Auto-assign public IP: Enable
- Security group: `lab-sg-a-linux`
- Key pair: `tgw-lab-key`

User data:

```bash
#!/bin/bash
hostnamectl set-hostname a2-linux
```

### B1 - Palo Alto Simulation

Create three ENIs manually first.

EC2 -> Network Interfaces -> Create:

- `palo-eni-untrust`: `subnet-b-untrust`, SG `lab-sg-palo-untrust`, private IP `10.1.1.10`, source/dest check disabled
- `palo-eni-trust`: `subnet-b-trust`, SG `lab-sg-palo-trust`, private IP `10.1.2.10`, source/dest check disabled
- `palo-eni-mgmt`: `subnet-b-mgmt`, SG `lab-sg-palo-mgmt`, private IP `10.1.3.10`, source/dest check enabled

Then launch B1:

- AMI: Amazon Linux 2023
- Type: `t3.medium`
- Do not select a subnet. Attach ENIs instead.
- Network: select `vpc-b`, remove the default NIC, and add the three ENIs.
- Device order: untrust as device `0`, trust as device `1`, mgmt as device `2`
- Key pair: `tgw-lab-key`
- No public IP. The EIP goes on the untrust ENI separately.

After launch, attach the `lab-eip-palo-untrust` EIP to the untrust ENI:

EC2 -> Elastic IPs -> select it -> Associate -> Network interface -> `palo-eni-untrust`.

### C1, C2, C3, D1

- AMI: Amazon Linux 2023
- Type: `t3.micro`
- No public IP
- Key pair: `tgw-lab-key`
- Private IPs and subnets as per the subnet layout
- Security groups as created in Phase 7

C1 user data:

```bash
#!/bin/bash
hostnamectl set-hostname c1-portal
dnf install -y nginx openssl
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/selfsigned.key \
  -out /etc/nginx/ssl/selfsigned.crt \
  -subj "/CN=lab.internal"
cat > /etc/nginx/conf.d/ssl.conf <<'EOF'
server {
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    location / { root /usr/share/nginx/html; index index.html; }
}
EOF
systemctl enable --now nginx
```

C2, C3, and D1 user data:

```bash
#!/bin/bash
hostnamectl set-hostname c2-gateway
python3 -m http.server 443 &
```

Change the hostname per instance.

### A1 - Windows

- AMI: Windows Server 2022
- Type: `t3.medium`
- VPC-A, `subnet-a`
- Public IP enabled
- SG: `lab-sg-a-windows`
- Key pair: `tgw-lab-key`, used to decrypt the Windows password

## Phase 13 - IAM Roles For A1 And A2

IAM -> Roles -> Create role -> AWS service -> EC2.

For A2, attach policies:

- `AmazonSSMManagedInstanceCore`
- `AmazonEC2ReadOnlyAccess`

Name it `lab-a2-diagnostic-role`. Create an instance profile with the same name.

EC2 -> Instances -> A2 -> Actions -> Security -> Modify IAM role -> attach `lab-a2-diagnostic-role`.

Repeat for A1 with `lab-a1-diagnostic-role`.

## Phase 14 - Verify

Connect to A2 via Session Manager and run the same verification commands from the previous playbook's Phase 8.

Expected:

- B1 returns `200`
- C1 returns `200`
- C2 returns `200`
- C3 returns `200`
- D1 returns `000`

## Things That Will Bite You In A Fresh Build

- TGW attachment subnet matters. The TGW ENI lands in whichever subnet you pick for the attachment. For VPC-B, always pick `subnet-b-trust` (`10.1.2.0/24`). All NACL and SG rules for transit traffic are written against that CIDR. If you attach to untrust or mgmt, the rules will not match.
- Default RT association and propagation must be disabled on both TGWs. If left enabled, AWS auto-associates every new attachment to the default RT and the spoke/firewall routing pattern gets bypassed silently.
- B1 needs source/dest check disabled on untrust and trust ENIs. The mgmt ENI should stay enabled.
- Appliance mode must be set at attachment creation time or modified immediately after. Without it, asymmetric traffic can cause intermittent HTTPS failures.
- The TGW attachment for VPC-C should be in `subnet-c-dmz`, not portal/gateway/controller. The DMZ subnet is the transit entry point.
- C1 nginx will not start if port `80` or `443` is already bound. If curl returns connection refused, SSH to C1 from A2 and run `sudo fuser -k 80/tcp 443/tcp && sudo systemctl restart nginx`.
- Session Manager will not work on A2 until the IAM role is attached and the SSM agent has checked in. Wait 2-3 minutes after attaching the role. If it still does not appear, reboot the instance.
- Windows password retrieval requires the private key. After A1 launches, go to EC2 -> Instances -> A1 -> Actions -> Security -> Get Windows password -> upload the `.pem` file. It can take up to 4 minutes after first boot.
- Route table TGW targets will not appear in the dropdown until the attachment is `Available`.
- VPC-A must not have a route to `10.3.0.0/16`. D1 must remain unreachable from VPC-A.
- NACLs are evaluated in rule number order, lowest first. Always number allow rules well below `32767` and check for conflicting rules before adding new ones.
- The NAT gateway must be in `subnet-a`, which has the IGW route.
- VPC-C and VPC-D have no IGW. They egress to the internet via TGW1 -> VPC-A -> NAT GW.
- The EIP for the Palo untrust ENI must be associated after B1 is running.
- When launching B1 with three ENIs, device index order matters: untrust device `0`, trust device `1`, mgmt device `2`.
- Session Manager requires outbound `443` from the instance to SSM endpoints. For VPC-C and VPC-D, Session Manager will not work until TGW routing and centralized egress are functional, so use A2 as a jump host during build.

## Complete Build Order Checklist

Use this as a tick-list. Do not move to the next item until the current one is confirmed.

### Networking Foundation

- [ ] VPC-A created (`10.0.0.0/16`)
- [ ] VPC-B created (`10.1.0.0/16`)
- [ ] VPC-C created (`10.2.0.0/16`)
- [ ] VPC-D created (`10.3.0.0/16`)
- [ ] `subnet-a` created and tagged
- [ ] `subnet-b-untrust` created and tagged
- [ ] `subnet-b-trust` created and tagged
- [ ] `subnet-b-mgmt` created and tagged
- [ ] `subnet-c-dmz` created and tagged
- [ ] `subnet-c-portal` created and tagged
- [ ] `subnet-c-gateway` created and tagged
- [ ] `subnet-c-controller` created and tagged
- [ ] `subnet-d` created and tagged
- [ ] `lab-igw-a` created and attached to `vpc-a`
- [ ] `lab-igw-b` created and attached to `vpc-b`
- [ ] EIP for NAT GW allocated
- [ ] EIP for Palo untrust allocated
- [ ] `lab-nat-gw` created in `subnet-a`, status `Available`

### Route Tables - TGW Targets Left Blank For Now

- [ ] `lab-rt-a` created, associated to `subnet-a`
- [ ] `lab-rt-b-untrust` created, associated to `subnet-b-untrust`
- [ ] `lab-rt-b-trust` created, associated to `subnet-b-trust`
- [ ] `lab-rt-b-mgmt` created, associated to `subnet-b-mgmt`
- [ ] `lab-rt-c-dmz` created, associated to `subnet-c-dmz`
- [ ] `lab-rt-c-portal` created, associated to `subnet-c-portal`
- [ ] `lab-rt-c-gateway` created, associated to `subnet-c-gateway`
- [ ] `lab-rt-c-controller` created, associated to `subnet-c-controller`
- [ ] `lab-rt-d` created, associated to `subnet-d`
- [ ] IGW and NAT GW routes added to all route tables that need them

### NACLs

- [ ] `nacl-a` created, associated to `subnet-a`, rules added
- [ ] `nacl-b-untrust` created, associated to `subnet-b-untrust`, rules added
- [ ] `nacl-b-trust` created, associated to `subnet-b-trust`, rules added, including `10.1.2.0/24` transit rules
- [ ] `nacl-b-mgmt` created, associated to `subnet-b-mgmt`, rules added
- [ ] `nacl-c-dmz` created, associated to `subnet-c-dmz`, rules added, including `10.1.2.0/24` ingress
- [ ] `nacl-c-portal` created, associated to `subnet-c-portal`, rules added, including `10.1.2.0/24` ingress and egress ephemeral
- [ ] `nacl-c-gateway` created, associated to `subnet-c-gateway`, rules added
- [ ] `nacl-c-controller` created, associated to `subnet-c-controller`, rules added
- [ ] `nacl-d` created, associated to `subnet-d`, rules added

### Security Groups

- [ ] `lab-sg-a-linux` created in `vpc-a`
- [ ] `lab-sg-a-windows` created in `vpc-a`
- [ ] `lab-sg-palo-untrust` created in `vpc-b`
- [ ] `lab-sg-palo-trust` created in `vpc-b`, including `10.1.2.0/24` ingress
- [ ] `lab-sg-palo-mgmt` created in `vpc-b`
- [ ] `lab-sg-c1-portal` created in `vpc-c`, including `10.1.2.0/24` TCP `443` ingress
- [ ] `lab-sg-c2-gateway` created in `vpc-c`, including `10.1.2.0/24` TCP `443` ingress
- [ ] `lab-sg-c3-controller` created in `vpc-c`, including `10.1.2.0/24` TCP `443` ingress
- [ ] `lab-sg-vpc-d` created in `vpc-d`

### Transit Gateways

- [ ] `lab-tgw1-mgmt` created, default RT association disabled, default RT propagation disabled, status `Available`
- [ ] `lab-tgw2-customer` created, default RT association disabled, default RT propagation disabled, status `Available`

### TGW Attachments

- [ ] `tgw1-attach-vpc-a` created (`subnet-a`), appliance mode disabled, status `Available`
- [ ] `tgw1-attach-vpc-b` created (`subnet-b-trust`), appliance mode enabled, status `Available`
- [ ] `tgw1-attach-vpc-c` created (`subnet-c-dmz`), appliance mode disabled, status `Available`
- [ ] `tgw2-attach-vpc-b` created (`subnet-b-trust`), appliance mode enabled, status `Available`
- [ ] `tgw2-attach-vpc-c` created (`subnet-c-dmz`), appliance mode disabled, status `Available`
- [ ] `tgw2-attach-vpc-d` created (`subnet-d`), appliance mode disabled, status `Available`

### Route Table TGW Targets

- [ ] `lab-rt-a`: TGW1 routes added (`10.1.0.0/16`, `10.2.0.0/16`)
- [ ] `lab-rt-b-untrust`: TGW1 and TGW2 routes added
- [ ] `lab-rt-b-trust`: TGW1 and TGW2 routes added
- [ ] `lab-rt-c-dmz`, `lab-rt-c-portal`, `lab-rt-c-gateway`, `lab-rt-c-controller`: TGW1 default and specific routes added
- [ ] `lab-rt-d`: TGW2 routes added

### TGW Route Tables - Model 2+3 Pattern

- [ ] `tgw1-rt-spoke` created, status `Available`
- [ ] `tgw1-rt-firewall` created, status `Available`
- [ ] `tgw2-rt-spoke` created, status `Available`
- [ ] `tgw2-rt-firewall` created, status `Available`
- [ ] `tgw1-rt-spoke` routes populated: `0.0.0.0/0` -> VPC-B
- [ ] `tgw1-rt-firewall` routes populated: `0.0.0.0/0` and `10.0.0.0/16` -> VPC-A; `10.2.0.0/16` -> VPC-C
- [ ] `tgw2-rt-spoke` routes populated: `0.0.0.0/0` -> VPC-B
- [ ] `tgw2-rt-firewall` routes populated: `0.0.0.0/0` and `10.1.0.0/16` -> VPC-B; `10.2.0.0/16` -> VPC-C; `10.3.0.0/16` -> VPC-D

### Association Cutover

- [ ] TGW1: VPC-A disassociated from default RT, associated to `tgw1-rt-spoke`
- [ ] TGW1: VPC-B disassociated from default RT, associated to `tgw1-rt-firewall`
- [ ] TGW1: VPC-C disassociated from default RT, associated to `tgw1-rt-spoke`
- [ ] TGW2: VPC-D disassociated from default RT, associated to `tgw2-rt-spoke`
- [ ] TGW2: VPC-B disassociated from default RT, associated to `tgw2-rt-firewall`
- [ ] TGW2: VPC-C disassociated from default RT, associated to `tgw2-rt-spoke`

### IAM

- [ ] `lab-a2-diagnostic-role` created with `AmazonSSMManagedInstanceCore` and `AmazonEC2ReadOnlyAccess`
- [ ] `lab-a1-diagnostic-role` created with `AmazonSSMManagedInstanceCore` and `AmazonEC2ReadOnlyAccess`

### Key Pair

- [ ] `tgw-lab-key` created, `.pem` downloaded and saved

### EC2 Instances

- [ ] `palo-eni-untrust` created (`10.1.1.10`, source/dest check off)
- [ ] `palo-eni-trust` created (`10.1.2.10`, source/dest check off)
- [ ] `palo-eni-mgmt` created (`10.1.3.10`, source/dest check on)
- [ ] A2 launched, IAM role attached, Session Manager reachable
- [ ] B1 launched with three ENIs, EIP associated to untrust ENI
- [ ] C1 launched, nginx running, curl from A2 returns `200`
- [ ] C2 launched, listener running, curl from A2 returns `200`
- [ ] C3 launched, listener running, curl from A2 returns `200`
- [ ] D1 launched
- [ ] A1 launched, Windows password retrieved

### Verification

- [ ] From A2 via Session Manager: B1 HTTPS = `200`
- [ ] From A2 via Session Manager: C1 HTTP = `200`
- [ ] From A2 via Session Manager: C1 HTTPS = `200`
- [ ] From A2 via Session Manager: C2 HTTPS = `200`
- [ ] From A2 via Session Manager: C3 HTTPS = `200`
- [ ] From A2 via Session Manager: D1 HTTP = `000` blocked
- [ ] Symmetry test: 10/10 requests to C1 pass

