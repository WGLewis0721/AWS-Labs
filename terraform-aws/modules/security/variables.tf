variable "name_prefix" {
  type        = string
  description = "Prefix used for naming security resources."
}

variable "management_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to access public management services in VPC-A."
  default     = ["0.0.0.0/0"]
}

variable "vpc_cidrs" {
  type        = map(string)
  description = "CIDR blocks keyed by lab segment."
}

variable "vpc_ids" {
  type        = map(string)
  description = "VPC IDs keyed by lab segment."
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to security resources."
  default     = {}
}
