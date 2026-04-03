variable "name_prefix" {
  type        = string
  description = "Prefix used for naming network resources."
}

variable "availability_zone" {
  type        = string
  description = "Optional availability zone override for all lab subnets."
  default     = null
}

variable "management_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the public management subnet in VPC-A."
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to network resources."
  default     = {}
}


