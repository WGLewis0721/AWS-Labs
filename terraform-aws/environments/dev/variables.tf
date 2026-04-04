variable "aws_region" {
  type        = string
  description = "AWS region for this environment."
}

variable "availability_zone" {
  type        = string
  description = "Optional AZ override for the single-subnet lab topology."
  default     = null
}

variable "public_key" {
  type        = string
  description = "SSH public key material for the tgw-lab-key EC2 key pair."
}

variable "management_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to access the public SSH and RDP endpoints in VPC-A."
  default     = ["0.0.0.0/0"]
}

variable "name_prefix" {
  type        = string
  description = "Prefix used for naming resources in this environment."
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags applied to all resources."
  default     = {}
}

variable "instance_ami_ids" {
  type        = map(string)
  description = "Optional AMI overrides keyed by lab node (a1, a2, b1, c1_portal, c2_gateway, c3_controller, d1)."
  default     = {}
}
