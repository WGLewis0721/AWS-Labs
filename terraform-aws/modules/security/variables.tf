variable "name_prefix" {
  type        = string
  description = "Prefix used for naming security resources."
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to security resources."
  default     = {}
}
