variable "name_prefix" {
  type        = string
  description = "Prefix used for naming compute resources."
}

variable "public_key" {
  type        = string
  description = "SSH public key material uploaded to AWS for Linux instance access."
}

variable "security_group_ids" {
  type        = map(string)
  description = "Security group IDs keyed by lab role."
}

variable "subnet_ids" {
  type        = map(string)
  description = "Subnet IDs keyed by lab segment."
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to compute resources."
  default     = {}
}
