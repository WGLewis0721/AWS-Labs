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
  b1_html = <<-HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Palo Alto NGFW Simulation</title>
    <style>
      body { font-family: "Segoe UI", sans-serif; margin: 0; background: linear-gradient(135deg, #041c32, #064663); color: #f7f7f7; }
      main { max-width: 720px; margin: 8rem auto; padding: 2rem; background: rgba(0, 0, 0, 0.28); border: 1px solid rgba(255, 255, 255, 0.18); border-radius: 24px; }
      h1 { margin-top: 0; font-size: 2.5rem; }
      p { line-height: 1.6; }
      .badge { display: inline-block; padding: 0.35rem 0.75rem; border-radius: 999px; background: #00c2a8; color: #04293a; font-weight: 700; }
    </style>
  </head>
  <body>
    <main>
      <span class="badge">B1</span>
      <h1>Palo Alto NGFW Simulation</h1>
      <p>This host represents the inspection tier connected to both transit gateways.</p>
      <p>Expected reachability: VPC-A and VPC-D can reach this node over TCP/80, while VPC-A remains isolated from VPC-D.</p>
    </main>
  </body>
  </html>
  HTML

  c1_html = <<-HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <title>AppGate SDP Simulation</title>
    <style>
      body { font-family: "Segoe UI", sans-serif; margin: 0; background: radial-gradient(circle at top, #2f4858, #0b132b 60%); color: #f9fafb; }
      main { max-width: 720px; margin: 8rem auto; padding: 2rem; background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.14); border-radius: 24px; }
      h1 { margin-top: 0; font-size: 2.5rem; }
      p { line-height: 1.6; }
      .badge { display: inline-block; padding: 0.35rem 0.75rem; border-radius: 999px; background: #ffd166; color: #1f2937; font-weight: 700; }
    </style>
  </head>
  <body>
    <main>
      <span class="badge">C1</span>
      <h1>AppGate SDP Simulation</h1>
      <p>This host represents the application access tier attached to both segmented transit gateways.</p>
      <p>Expected reachability: VPC-A and VPC-D can load this page over HTTP, with no routed path between VPC-A and VPC-D.</p>
    </main>
  </body>
  </html>
  HTML

  linux_web_userdata_template = <<-EOT
  #!/bin/bash
  set -euxo pipefail

  hostnamectl set-hostname $${HOSTNAME}
  mkdir -p /opt/lab-web
  cat > /opt/lab-web/index.html <<'HTML'
  $${HTML}
  HTML

  cat > /etc/systemd/system/lab-web.service <<'SERVICE'
  [Unit]
  Description=TGW lab static web service
  After=network-online.target
  Wants=network-online.target

  [Service]
  Type=simple
  WorkingDirectory=/opt/lab-web
  ExecStart=/usr/bin/python3 -m http.server 80 --bind 0.0.0.0
  Restart=always
  User=root

  [Install]
  WantedBy=multi-user.target
  SERVICE

  systemctl daemon-reload
  systemctl enable --now lab-web.service
  EOT

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

  b1_userdata = replace(
    replace(local.linux_web_userdata_template, "$${HOSTNAME}", "b1-paloalto"),
    "$${HTML}",
    trimspace(local.b1_html)
  )

  c1_userdata = replace(
    replace(local.linux_web_userdata_template, "$${HOSTNAME}", "c1-appgate"),
    "$${HTML}",
    trimspace(local.c1_html)
  )

  d1_userdata = <<-BASH
  #!/bin/bash
  set -euxo pipefail
  hostnamectl set-hostname d1-customer
  cat > /home/ec2-user/lab-notes.txt <<'EOF'
  D1 is the customer test client. It should reach B1 and C1 over TGW-2 only.
  EOF
  chown ec2-user:ec2-user /home/ec2-user/lab-notes.txt
  BASH

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
    b1 = {
      ami_id        = data.aws_ami.al2023.id
      instance_type = "t3.micro"
      name          = "lab-b1-paloalto"
      private_ip    = "10.1.1.10"
      public_ip     = false
      role          = "paloalto-sim"
      root_volume   = 30
      security_key  = "b"
      subnet_key    = "b"
      user_data     = local.b1_userdata
      windows       = false
    }
    c1 = {
      ami_id        = data.aws_ami.al2023.id
      instance_type = "t3.micro"
      name          = "lab-c1-appgate"
      private_ip    = "10.2.1.10"
      public_ip     = false
      role          = "appgate-sim"
      root_volume   = 30
      security_key  = "c"
      subnet_key    = "c"
      user_data     = local.c1_userdata
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

resource "aws_key_pair" "lab" {
  key_name   = "tgw-lab-key"
  public_key = trimspace(var.public_key)

  tags = merge(
    var.tags,
    {
      Name = "tgw-lab-key"
    }
  )
}

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
