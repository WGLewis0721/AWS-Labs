resource "aws_default_security_group" "this" {
  for_each = var.vpc_ids

  vpc_id = each.value

  ingress = []
  egress  = []

  tags = merge(
    var.tags,
    {
      Name = "default-sg-vpc-${each.key}"
    }
  )
}

resource "aws_security_group" "a_windows" {
  description = "RDP access for the Windows browser host in VPC-A."
  name        = "lab-sg-a-windows"
  vpc_id      = var.vpc_ids["a"]

  ingress {
    cidr_blocks = var.management_cidrs
    description = "RDP from management CIDRs"
    from_port   = 3389
    protocol    = "tcp"
    to_port     = 3389
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Internet and lab egress for Windows host"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = merge(
    var.tags,
    {
      Name = "lab-sg-a-windows"
    }
  )
}

resource "aws_security_group" "a_linux" {
  description = "SSH access for the Linux jump host in VPC-A."
  name        = "lab-sg-a-linux"
  vpc_id      = var.vpc_ids["a"]

  ingress {
    cidr_blocks = var.management_cidrs
    description = "SSH from management CIDRs"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Internet and lab egress for Linux jump host"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = merge(
    var.tags,
    {
      Name = "lab-sg-a-linux"
    }
  )
}

resource "aws_security_group" "b" {
  description = "Palo Alto simulation security group."
  name        = "lab-sg-vpc-b"
  vpc_id      = var.vpc_ids["b"]

  ingress {
    cidr_blocks = [var.vpc_cidrs["a"], var.vpc_cidrs["c"]]
    description = "SSH from VPC-A jump host and VPC-C"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  ingress {
    cidr_blocks = [var.vpc_cidrs["a"], var.vpc_cidrs["c"], var.vpc_cidrs["d"]]
    description = "HTTP from management, customer, and AppGate segments"
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }

  ingress {
    cidr_blocks = [var.vpc_cidrs["a"], var.vpc_cidrs["c"], var.vpc_cidrs["d"]]
    description = "ICMP from connected segments"
    from_port   = -1
    protocol    = "icmp"
    to_port     = -1
  }

  egress {
    cidr_blocks = [var.vpc_cidrs["a"], var.vpc_cidrs["c"], var.vpc_cidrs["d"]]
    description = "Scoped internal egress"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = merge(
    var.tags,
    {
      Name = "lab-sg-vpc-b"
    }
  )
}

resource "aws_security_group" "c" {
  description = "AppGate simulation security group."
  name        = "lab-sg-vpc-c"
  vpc_id      = var.vpc_ids["c"]

  ingress {
    cidr_blocks = [var.vpc_cidrs["a"], var.vpc_cidrs["b"]]
    description = "SSH from VPC-A jump host and VPC-B"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  ingress {
    cidr_blocks = [var.vpc_cidrs["a"], var.vpc_cidrs["b"], var.vpc_cidrs["d"]]
    description = "HTTP from management, customer, and Palo Alto segments"
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }

  ingress {
    cidr_blocks = [var.vpc_cidrs["a"], var.vpc_cidrs["b"], var.vpc_cidrs["d"]]
    description = "ICMP from connected segments"
    from_port   = -1
    protocol    = "icmp"
    to_port     = -1
  }

  egress {
    cidr_blocks = [var.vpc_cidrs["a"], var.vpc_cidrs["b"], var.vpc_cidrs["d"]]
    description = "Scoped internal egress"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = merge(
    var.tags,
    {
      Name = "lab-sg-vpc-c"
    }
  )
}

resource "aws_security_group" "d" {
  description = "Customer test client security group."
  name        = "lab-sg-vpc-d"
  vpc_id      = var.vpc_ids["d"]

  ingress {
    cidr_blocks = [var.vpc_cidrs["b"]]
    description = "SSH from Palo Alto simulation"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  ingress {
    cidr_blocks = [var.vpc_cidrs["b"]]
    description = "ICMP from Palo Alto simulation"
    from_port   = -1
    protocol    = "icmp"
    to_port     = -1
  }

  egress {
    cidr_blocks = [var.vpc_cidrs["b"], var.vpc_cidrs["c"]]
    description = "Scoped internal egress to reachable segments"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = merge(
    var.tags,
    {
      Name = "lab-sg-vpc-d"
    }
  )
}
