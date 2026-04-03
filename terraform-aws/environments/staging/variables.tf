variable "aws_region" {
  type        = string
  description = "AWS region for this environment."
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
