variable "name_prefix" {
  type        = string
  description = "Prefix used for naming network resources."
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to network resources."
  default     = {}
}
