data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

locals {
  # ---------------------------------------------------------------------------
  # HTML page content
  # ---------------------------------------------------------------------------

  b1_html = <<-HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <title>VPC-B | Palo Alto VM-Series NGFW</title>
    <style>
      body { font-family: "Segoe UI", sans-serif; margin: 0; background: linear-gradient(135deg, #041c32, #064663); color: #f7f7f7; }
      main { max-width: 720px; margin: 8rem auto; padding: 2rem; background: rgba(0,0,0,0.28); border: 1px solid rgba(255,255,255,0.18); border-radius: 24px; }
      h1 { margin-top: 0; font-size: 2.5rem; }
      p { line-height: 1.6; }
      .badge { display: inline-block; padding: 0.35rem 0.75rem; border-radius: 999px; background: #00c2a8; color: #04293a; font-weight: 700; }
      table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
      td, th { border: 1px solid rgba(255,255,255,0.2); padding: 0.5rem 1rem; text-align: left; }
    </style>
  </head>
  <body>
    <main>
      <span class="badge">B1</span>
      <h1>Palo Alto VM-Series NGFW</h1>
      <p>Three-ENI deployment simulating real Palo Alto VM-Series architecture.</p>
      <table>
        <tr><th>Interface</th><th>IP</th><th>Role</th><th>source_dest_check</th></tr>
        <tr><td>eth0 (UNTRUST)</td><td>10.1.1.10</td><td>Internet-facing</td><td>false</td></tr>
        <tr><td>eth1 (TRUST)</td><td>10.1.2.10</td><td>Post-inspection egress</td><td>false</td></tr>
        <tr><td>eth2 (MGMT)</td><td>10.1.3.10</td><td>Management plane</td><td>true</td></tr>
      </table>
      <p>source_dest_check=false on UNTRUST and TRUST ENIs is mandatory — Palo routes others' traffic.</p>
    </main>
  </body>
  </html>
  HTML

  c1_portal_html = <<-HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <title>VPC-C | AppGate SDP — Portal</title>
    <style>
      body { font-family: "Segoe UI", sans-serif; margin: 0; background: radial-gradient(circle at top, #2f4858, #0b132b 60%); color: #f9fafb; }
      main { max-width: 720px; margin: 8rem auto; padding: 2rem; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.14); border-radius: 24px; }
      h1 { margin-top: 0; font-size: 2.5rem; }
      p { line-height: 1.6; }
      .badge { display: inline-block; padding: 0.35rem 0.75rem; border-radius: 999px; background: #ffd166; color: #1f2937; font-weight: 700; }
    </style>
  </head>
  <body>
    <main>
      <span class="badge">c1-portal</span>
      <h1>AppGate SDP — Portal</h1>
      <p>Role: Clientless Browser Access Point</p>
      <p>Subnet: subnet-c-portal | 10.2.2.10</p>
      <p>Function: Receives customer browser sessions. Performs SPA on customer's behalf. No AppGate client required on endpoint.</p>
      <p>Reachable from: VPC-B trust side via TGW1 (post-Palo inspection)</p>
      <p>NOT reachable from: Internet directly</p>
    </main>
  </body>
  </html>
  HTML

  c2_gateway_html = <<-HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <title>VPC-C | AppGate SDP — Gateway</title>
    <style>
      body { font-family: "Segoe UI", sans-serif; margin: 0; background: radial-gradient(circle at top, #2f4858, #0b132b 60%); color: #f9fafb; }
      main { max-width: 720px; margin: 8rem auto; padding: 2rem; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.14); border-radius: 24px; }
      h1 { margin-top: 0; font-size: 2.5rem; }
      p { line-height: 1.6; }
      .badge { display: inline-block; padding: 0.35rem 0.75rem; border-radius: 999px; background: #06d6a0; color: #1f2937; font-weight: 700; }
    </style>
  </head>
  <body>
    <main>
      <span class="badge">c2-gateway</span>
      <h1>AppGate SDP — Gateway</h1>
      <p>Role: Policy Enforcement Point</p>
      <p>Subnet: subnet-c-gateway | 10.2.3.10</p>
      <p>Function: Enforces per-user encrypted micro-tunnels (segment of one). Customer data flows through here after Portal authentication. Only entitled resources visible — everything else cloaked.</p>
      <p>Reachable from: Portal (10.2.2.0/24), Controller (10.2.4.0/24), VPC-A mgmt</p>
      <p>NOT reachable from: Internet, VPC-D directly</p>
    </main>
  </body>
  </html>
  HTML

  c3_controller_html = <<-HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <title>VPC-C | AppGate SDP — Controller</title>
    <style>
      body { font-family: "Segoe UI", sans-serif; margin: 0; background: radial-gradient(circle at top, #2f4858, #0b132b 60%); color: #f9fafb; }
      main { max-width: 720px; margin: 8rem auto; padding: 2rem; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.14); border-radius: 24px; }
      h1 { margin-top: 0; font-size: 2.5rem; }
      p { line-height: 1.6; }
      .badge { display: inline-block; padding: 0.35rem 0.75rem; border-radius: 999px; background: #ef476f; color: #fff; font-weight: 700; }
    </style>
  </head>
  <body>
    <main>
      <span class="badge">c3-controller</span>
      <h1>AppGate SDP — Controller</h1>
      <p>Role: Policy Administrator + Policy Engine</p>
      <p>Subnet: subnet-c-controller | 10.2.4.10</p>
      <p>Function: Authenticates users via IdP (MFA). Evaluates entitlements and context. Issues session tokens to Gateway. NEVER in customer data path — control plane only.</p>
      <p>Admin UI: https://10.2.4.10:8443 (reachable from VPC-A only)</p>
      <p>Peer port: 444 (appliance-to-appliance communication)</p>
      <p>Reachable from: VPC-A management only (ports 8443, 444, 22)</p>
      <p>NOT reachable from: Internet, VPC-D, customer path</p>
    </main>
  </body>
  </html>
  HTML

  # ---------------------------------------------------------------------------
  # User-data: static instances (A1, A2, D1)
  # ---------------------------------------------------------------------------

  a1_userdata = <<-POWERSHELL
  <powershell>
  $ProgressPreference = 'SilentlyContinue'
  Rename-Computer -NewName "A1-WINDOWS" -Force
  $chromeInstaller = "$env:TEMP\\chrome_installer.exe"
  Invoke-WebRequest -Uri "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $chromeInstaller
  Start-Process -FilePath $chromeInstaller -ArgumentList "/silent /install" -Wait
  New-Item -Path "C:\\lab" -ItemType Directory -Force | Out-Null
  Set-Content -Path "C:\\lab\\README.txt" -Value "Use Chrome to verify HTTP reachability to B1 and C1."
  </powershell>
  POWERSHELL

  a2_userdata = <<-BASH
  #!/bin/bash
  set -euxo pipefail
  hostnamectl set-hostname a2-linux
  cat > /home/ec2-user/lab-notes.txt <<'EOF'
  A2 is the public Linux jump host for the TGW segmentation lab.
  Use the test_commands output after apply for the full connectivity matrix.
  EOF
  chown ec2-user:ec2-user /home/ec2-user/lab-notes.txt
  BASH

  d1_userdata = <<-BASH
  #!/bin/bash
  set -euxo pipefail
  hostnamectl set-hostname d1-customer
  cat > /home/ec2-user/lab-notes.txt <<'EOF'
  D1 is the customer test client. It should reach B1 and C1 over TGW-2 only.
  EOF
  chown ec2-user:ec2-user /home/ec2-user/lab-notes.txt
  BASH

  b1_post_boot = <<-BASH
  cat > /usr/local/bin/lab-configure-multi-eni.sh <<'SCRIPT'
  #!/bin/bash
  set -euxo pipefail

  ensure_table() {
    local id="$1"
    local name="$2"
    grep -qE "^$${id}[[:space:]]+$${name}$" /etc/iproute2/rt_tables || echo "$${id} $${name}" >> /etc/iproute2/rt_tables
  }

  ensure_table 101 palo-untrust
  ensure_table 102 palo-trust
  ensure_table 103 palo-mgmt

  sysctl -w net.ipv4.conf.all.rp_filter=0
  sysctl -w net.ipv4.conf.default.rp_filter=0
  sysctl -w net.ipv4.conf.ens5.rp_filter=0
  sysctl -w net.ipv4.conf.ens6.rp_filter=0
  sysctl -w net.ipv4.conf.ens7.rp_filter=0

  ip route flush table 101 || true
  ip route flush table 102 || true
  ip route flush table 103 || true

  ip route replace 10.1.1.0/24 dev ens5 src 10.1.1.10 table 101
  ip route replace default via 10.1.1.1 dev ens5 table 101
  ip route replace 10.1.2.0/24 dev ens6 src 10.1.2.10 table 102
  ip route replace default via 10.1.2.1 dev ens6 table 102
  ip route replace 10.1.3.0/24 dev ens7 src 10.1.3.10 table 103
  ip route replace default via 10.1.3.1 dev ens7 table 103

  ip rule del from 10.1.1.10/32 table 101 priority 100 2>/dev/null || true
  ip rule del from 10.1.2.10/32 table 102 priority 101 2>/dev/null || true
  ip rule del from 10.1.3.10/32 table 103 priority 102 2>/dev/null || true

  ip rule add from 10.1.1.10/32 table 101 priority 100
  ip rule add from 10.1.2.10/32 table 102 priority 101
  ip rule add from 10.1.3.10/32 table 103 priority 102

  ip route flush cache
  SCRIPT
  chmod +x /usr/local/bin/lab-configure-multi-eni.sh

  cat > /etc/systemd/system/lab-multi-eni.service <<'SERVICE'
  [Unit]
  Description=Configure source-based routing for the Palo multi-ENI host
  After=network-online.target
  Wants=network-online.target

  [Service]
  Type=oneshot
  ExecStart=/usr/local/bin/lab-configure-multi-eni.sh
  RemainAfterExit=yes

  [Install]
  WantedBy=multi-user.target
  SERVICE

  systemctl daemon-reload
  systemctl enable --now lab-multi-eni.service
  BASH

  # ---------------------------------------------------------------------------
  # User-data: self-contained HTTP + HTTPS template
  # Avoid package-manager dependencies so the landing pages still come up
  # before centralized egress is fully validated.
  # ---------------------------------------------------------------------------

  web_userdata_template = <<-EOT
  #!/bin/bash
  set -euxo pipefail
  hostnamectl set-hostname $${HOSTNAME}
  mkdir -p /opt/lab-web
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /opt/lab-web/self.key \
    -out /opt/lab-web/self.crt \
    -subj "/CN=lab.internal/O=TGW Lab"
  cat > /opt/lab-web/index.html <<'HTML'
  $${HTML}
  HTML
  cat > /opt/lab-web/server.py <<'PY'
  import http.server
  import os
  import socketserver
  import ssl
  import threading

  os.chdir("/opt/lab-web")

  class ReusableTCPServer(socketserver.TCPServer):
      allow_reuse_address = True

  class Handler(http.server.SimpleHTTPRequestHandler):
      def log_message(self, fmt, *args):
          return

  def serve_http():
      with ReusableTCPServer(("0.0.0.0", 80), Handler) as httpd:
          httpd.serve_forever()

  def serve_https():
      with ReusableTCPServer(("0.0.0.0", 443), Handler) as httpd:
          context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
          context.load_cert_chain("/opt/lab-web/self.crt", "/opt/lab-web/self.key")
          httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
          httpd.serve_forever()

  threading.Thread(target=serve_http, daemon=True).start()
  serve_https()
  PY
  cat > /etc/systemd/system/lab-web.service <<'SERVICE'
  [Unit]
  Description=TGW Lab static HTTP/HTTPS landing page
  After=network-online.target
  Wants=network-online.target

  [Service]
  Type=simple
  ExecStart=/usr/bin/python3 /opt/lab-web/server.py
  Restart=always
  RestartSec=5
  WorkingDirectory=/opt/lab-web

  [Install]
  WantedBy=multi-user.target
  SERVICE
  systemctl daemon-reload
  systemctl enable --now sshd
  systemctl enable --now lab-web.service
  $${POST_BOOT}
  EOT

  b1_userdata = replace(
    replace(
      replace(local.web_userdata_template, "$${HOSTNAME}", "b1-paloalto"),
      "$${HTML}",
      trimspace(local.b1_html)
    ),
    "$${POST_BOOT}",
    trimspace(local.b1_post_boot)
  )

  c1_portal_userdata = replace(<<-BASH
  #!/bin/bash
  set -euxo pipefail
  hostnamectl set-hostname c1-portal

  # Best-effort cleanup if a prior placeholder server is already bound.
  command -v fuser >/dev/null 2>&1 && fuser -k 80/tcp 2>/dev/null || true
  command -v fuser >/dev/null 2>&1 && fuser -k 443/tcp 2>/dev/null || true

  dnf install -y nginx openssl psmisc

  fuser -k 80/tcp 2>/dev/null || true
  fuser -k 443/tcp 2>/dev/null || true

  mkdir -p /etc/nginx/ssl
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/selfsigned.key \
    -out /etc/nginx/ssl/selfsigned.crt \
    -subj "/CN=appgate-sim.lab/O=TGW-Lab/C=US"

  cat > /usr/share/nginx/html/index.html <<'HTML'
  __HTML__
  HTML

  cat > /etc/nginx/conf.d/ssl.conf <<'NGINXCONF'
  server {
      listen 443 ssl;
      server_name _;
      ssl_certificate /etc/nginx/ssl/selfsigned.crt;
      ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
      location / {
          root /usr/share/nginx/html;
          index index.html;
      }
  }
  NGINXCONF

  systemctl enable --now sshd
  systemctl enable nginx
  systemctl restart nginx
  BASH
  , "__HTML__", trimspace(local.c1_portal_html))

  c2_gateway_userdata = replace(
    replace(
      replace(local.web_userdata_template, "$${HOSTNAME}", "c2-gateway"),
      "$${HTML}",
      trimspace(local.c2_gateway_html)
    ),
    "$${POST_BOOT}",
    ""
  )

  c3_controller_userdata = replace(
    replace(
      replace(local.web_userdata_template, "$${HOSTNAME}", "c3-controller"),
      "$${HTML}",
      trimspace(local.c3_controller_html)
    ),
    "$${POST_BOOT}",
    ""
  )

  # ---------------------------------------------------------------------------
  # Instance map — used by aws_instance.this (excludes B1)
  # ---------------------------------------------------------------------------

  instances = {
    a1 = {
      ami_id        = data.aws_ami.windows_2022.id
      instance_type = "t3.medium"
      name          = "lab-a1-windows"
      private_ip    = "10.0.1.10"
      public_ip     = true
      role          = "windows-browser"
      root_volume   = 50
      security_key  = "a_windows"
      subnet_key    = "a"
      user_data     = local.a1_userdata
      windows       = true
    }
    a2 = {
      ami_id        = data.aws_ami.al2023.id
      instance_type = "t3.micro"
      name          = "lab-a2-linux"
      private_ip    = "10.0.1.20"
      public_ip     = true
      role          = "linux-jump"
      root_volume   = 30
      security_key  = "a_linux"
      subnet_key    = "a"
      user_data     = local.a2_userdata
      windows       = false
    }
    c1_portal = {
      ami_id        = data.aws_ami.al2023.id
      instance_type = "t3.micro"
      name          = "lab-c1-portal"
      private_ip    = "10.2.2.10"
      public_ip     = false
      role          = "appgate-portal"
      root_volume   = 30
      security_key  = "c1_portal"
      subnet_key    = "c_portal"
      user_data     = local.c1_portal_userdata
      windows       = false
    }
    c2_gateway = {
      ami_id        = data.aws_ami.al2023.id
      instance_type = "t3.micro"
      name          = "lab-c2-gateway"
      private_ip    = "10.2.3.10"
      public_ip     = false
      role          = "appgate-gateway"
      root_volume   = 30
      security_key  = "c2_gateway"
      subnet_key    = "c_gateway"
      user_data     = local.c2_gateway_userdata
      windows       = false
    }
    c3_controller = {
      ami_id        = data.aws_ami.al2023.id
      instance_type = "t3.micro"
      name          = "lab-c3-controller"
      private_ip    = "10.2.4.10"
      public_ip     = false
      role          = "appgate-controller"
      root_volume   = 30
      security_key  = "c3_controller"
      subnet_key    = "c_controller"
      user_data     = local.c3_controller_userdata
      windows       = false
    }
    d1 = {
      ami_id        = data.aws_ami.al2023.id
      instance_type = "t3.micro"
      name          = "lab-d1-customer"
      private_ip    = "10.3.1.10"
      public_ip     = false
      role          = "customer-client"
      root_volume   = 30
      security_key  = "d"
      subnet_key    = "d"
      user_data     = local.d1_userdata
      windows       = false
    }
  }
}

# ---------------------------------------------------------------------------
# SSH key pair
# ---------------------------------------------------------------------------

resource "aws_key_pair" "lab" {
  key_name   = "tgw-lab-key"
  public_key = trimspace(var.public_key)

  tags = merge(var.tags, { Name = "tgw-lab-key" })
}

# ---------------------------------------------------------------------------
# Palo Alto standalone ENIs (three-ENI deployment)
# ---------------------------------------------------------------------------

resource "aws_network_interface" "palo_untrust" {
  subnet_id         = var.subnet_ids["b_untrust"]
  private_ips       = ["10.1.1.10"]
  source_dest_check = false
  security_groups   = [var.security_group_ids["palo_untrust"]]

  tags = merge(var.tags, { Name = "palo-eni-untrust" })
}

resource "aws_network_interface" "palo_trust" {
  subnet_id         = var.subnet_ids["b_trust"]
  private_ips       = ["10.1.2.10"]
  source_dest_check = false
  security_groups   = [var.security_group_ids["palo_trust"]]

  tags = merge(var.tags, { Name = "palo-eni-trust" })
}

resource "aws_network_interface" "palo_mgmt" {
  subnet_id         = var.subnet_ids["b_mgmt"]
  private_ips       = ["10.1.3.10"]
  source_dest_check = true
  security_groups   = [var.security_group_ids["palo_mgmt"]]

  tags = merge(var.tags, { Name = "palo-eni-mgmt" })
}

# ---------------------------------------------------------------------------
# EIP attached to Palo UNTRUST ENI
# ---------------------------------------------------------------------------

resource "aws_eip" "palo_untrust" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.palo_untrust.id
  associate_with_private_ip = "10.1.1.10"
  depends_on                = [aws_instance.b1]

  tags = merge(var.tags, { Name = "lab-eip-palo-untrust" })
}

# ---------------------------------------------------------------------------
# B1 — Palo Alto VM-Series simulation (three ENI attachments, no subnet_id)
# ---------------------------------------------------------------------------

resource "aws_instance" "b1" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.medium" # larger than t3.micro to simulate realistic firewall resource allocation
  key_name      = aws_key_pair.lab.key_name
  user_data     = local.b1_userdata

  user_data_replace_on_change = true

  # Placement is determined entirely by the attached ENIs — do NOT set subnet_id.
  network_interface {
    network_interface_id = aws_network_interface.palo_untrust.id
    device_index         = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.palo_trust.id
    device_index         = 1
  }
  network_interface {
    network_interface_id = aws_network_interface.palo_mgmt.id
    device_index         = 2
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = 30
    volume_type           = "gp3"
  }

  tags = merge(var.tags, {
    Name    = "lab-b1-paloalto"
    LabNode = "B1"
    Role    = "paloalto-sim"
  })
}

# ---------------------------------------------------------------------------
# All other instances (A1, A2, C1-portal, C2-gateway, C3-controller, D1)
# ---------------------------------------------------------------------------

resource "aws_instance" "this" {
  for_each = local.instances

  ami                         = each.value.ami_id
  associate_public_ip_address = each.value.public_ip
  get_password_data           = each.value.windows
  instance_type               = each.value.instance_type
  key_name                    = aws_key_pair.lab.key_name
  private_ip                  = each.value.private_ip
  subnet_id                   = var.subnet_ids[each.value.subnet_key]
  user_data                   = each.value.user_data
  user_data_replace_on_change = true
  vpc_security_group_ids      = [var.security_group_ids[each.value.security_key]]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = each.value.root_volume
    volume_type           = "gp3"
  }

  tags = merge(
    var.tags,
    {
      Name    = each.value.name
      LabNode = upper(each.key)
      Role    = each.value.role
    }
  )
}
