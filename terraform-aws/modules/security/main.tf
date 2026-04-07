resource "aws_default_security_group" "this" {
  for_each = var.vpc_ids

  vpc_id = each.value

  ingress = []
  egress  = []

  tags = merge(var.tags, { Name = "default-sg-vpc-${each.key}" })
}

# ── VPC-A ─────────────────────────────────────────────────────────────────────

resource "aws_security_group" "a_windows" {
  description = "RDP access for the Windows browser host in VPC-A."
  name        = "lab-sg-a-windows"
  vpc_id      = var.vpc_ids["a"]

  ingress {
    description = "RDP from operator"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.management_cidrs
  }

  ingress {
    description = "ICMP from RFC-1918"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "Return traffic from VPC-B"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  ingress {
    description = "Return traffic from VPC-C"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "lab-sg-a-windows" })
}

resource "aws_security_group" "a_linux" {
  description = "SSH access for the Linux jump host in VPC-A."
  name        = "lab-sg-a-linux"
  vpc_id      = var.vpc_ids["a"]

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.management_cidrs
  }

  ingress {
    description = "ICMP from RFC-1918"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "Return traffic from VPC-B"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  ingress {
    description = "Return traffic from VPC-C"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "lab-sg-a-linux" })
}

# ── VPC-B ─────────────────────────────────────────────────────────────────────

resource "aws_security_group" "palo_untrust" {
  description = "Palo Alto UNTRUST ENI (VPC-B)."
  name        = "lab-sg-palo-untrust"
  vpc_id      = var.vpc_ids["b"]

  ingress {
    description = "Customer HTTPS from ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from internal"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "lab-sg-palo-untrust" })
}

resource "aws_security_group" "palo_trust" {
  description = "Palo Alto TRUST ENI (VPC-B)."
  name        = "lab-sg-palo-trust"
  vpc_id      = var.vpc_ids["b"]

  ingress {
    description = "Ephemeral return from AppGate"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  ingress {
    description = "ICMP from internal"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "Return to VPC-A"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Toward AppGate (VPC-C)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.2.0.0/16"]
  }

  egress {
    description = "Return to customer VPC-D"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.3.0.0/16"]
  }

  tags = merge(var.tags, { Name = "lab-sg-palo-trust" })
}

resource "aws_security_group" "palo_mgmt" {
  description = "Palo Alto MGMT ENI (VPC-B)."
  name        = "lab-sg-palo-mgmt"
  vpc_id      = var.vpc_ids["b"]

  ingress {
    description = "SSH from VPC-A bastion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS mgmt console from VPC-A"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "ICMP from VPC-A"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "SSH from VPC-C"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  ingress {
    description = "HTTPS from VPC-C"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  egress {
    description = "Return to VPC-A"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Ephemeral return to VPC-C"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  egress {
    description = "Panorama and license updates via NAT GW"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "lab-sg-palo-mgmt" })
}

# ── VPC-C ─────────────────────────────────────────────────────────────────────

resource "aws_security_group" "c1_portal" {
  description = "AppGate c1-portal in subnet-c-portal (VPC-C)."
  name        = "lab-sg-c1-portal"
  vpc_id      = var.vpc_ids["c"]

  ingress {
    description = "Admin UI from VPC-A"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS management from VPC-A"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS transit from VPC-B trust (TGW inspection path)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.1.2.0/24"]
  }

  ingress {
    description = "HTTP management from VPC-A"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "SSH from VPC-A"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Gateway to Portal return"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.2.3.0/24"]
  }

  ingress {
    description = "ICMP from RFC-1918"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "HTTPS from VPC-D customer"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.3.0.0/16"]
  }

  egress {
    description = "Portal to Gateway tunnel"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.2.3.0/24"]
  }

  egress {
    description = "Portal to Controller peer"
    from_port   = 444
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["10.2.4.0/24"]
  }

  egress {
    description = "Portal to Controller peer (8443)"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["10.2.4.0/24"]
  }

  egress {
    description = "SSH to B1 mgmt"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.1.3.0/24"]
  }

  egress {
    description = "HTTPS to B1 mgmt"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.1.3.0/24"]
  }

  egress {
    description = "IdP calls via NAT GW"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Ephemeral return to VPC-A"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Ephemeral return to VPC-D"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.3.0.0/16"]
  }

  tags = merge(var.tags, { Name = "lab-sg-c1-portal" })
}

resource "aws_security_group" "c2_gateway" {
  description = "AppGate c2-gateway in subnet-c-gateway (VPC-C)."
  name        = "lab-sg-c2-gateway"
  vpc_id      = var.vpc_ids["c"]

  ingress {
    description = "Tunnel from Portal"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.2.2.0/24"]
  }

  ingress {
    description = "Admin from VPC-A"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS management from VPC-A"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS transit from VPC-B trust (TGW inspection path)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.1.2.0/24"]
  }

  ingress {
    description = "Peer interface from VPC-A"
    from_port   = 444
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "SSH from VPC-A"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Controller collective"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.2.4.0/24"]
  }

  ingress {
    description = "ICMP from RFC-1918"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "Return to Portal"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.2.2.0/24"]
  }

  egress {
    description = "Gateway to Controller peer"
    from_port   = 444
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["10.2.4.0/24"]
  }

  egress {
    description = "Gateway to Controller (8443)"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["10.2.4.0/24"]
  }

  egress {
    description = "License and updates via NAT GW"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Ephemeral return to VPC-A"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = merge(var.tags, { Name = "lab-sg-c2-gateway" })
}

resource "aws_security_group" "c3_controller" {
  description = "AppGate c3-controller in subnet-c-controller (VPC-C)."
  name        = "lab-sg-c3-controller"
  vpc_id      = var.vpc_ids["c"]

  ingress {
    description = "Admin from VPC-A"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS management from VPC-A"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "HTTPS transit from VPC-B trust (TGW inspection path)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.1.2.0/24"]
  }

  ingress {
    description = "Peer interface from VPC-A"
    from_port   = 444
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "SSH from VPC-A"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Portal to Controller (444)"
    from_port   = 444
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["10.2.2.0/24"]
  }

  ingress {
    description = "Portal to Controller (8443)"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["10.2.2.0/24"]
  }

  ingress {
    description = "Gateway to Controller (444)"
    from_port   = 444
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["10.2.3.0/24"]
  }

  ingress {
    description = "Gateway to Controller (8443)"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["10.2.3.0/24"]
  }

  ingress {
    description = "ICMP from RFC-1918"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description = "Controller to Portal (444)"
    from_port   = 444
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["10.2.2.0/24"]
  }

  egress {
    description = "Controller to Portal (8443)"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["10.2.2.0/24"]
  }

  egress {
    description = "Controller to Gateway (444)"
    from_port   = 444
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["10.2.3.0/24"]
  }

  egress {
    description = "Controller to Gateway (8443)"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["10.2.3.0/24"]
  }

  egress {
    description = "IdP and license via NAT GW"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Ephemeral return to VPC-A"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = merge(var.tags, { Name = "lab-sg-c3-controller" })
}

# ── VPC-D ─────────────────────────────────────────────────────────────────────

resource "aws_security_group" "d" {
  description = "Customer test client security group."
  name        = "lab-sg-vpc-d"
  vpc_id      = var.vpc_ids["d"]

  ingress {
    description = "SSH hop from VPC-B"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  ingress {
    description = "HTTP return from B1"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  ingress {
    description = "HTTP return from C1"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  ingress {
    description = "HTTPS from VPC-C AppGate"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  ingress {
    description = "ICMP from VPC-B"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  egress {
    description = "HTTP to Palo service tier"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  egress {
    description = "HTTPS to Palo service tier"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  egress {
    description = "HTTPS to AppGate service tier"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  egress {
    description = "Ephemeral return to VPC-C"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.2.0.0/16"]
  }

  tags = merge(var.tags, { Name = "lab-sg-vpc-d" })
}
