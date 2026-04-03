variable "name_prefix" {
  type        = string
  description = "Prefix used for naming compute resources."
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to compute resources."
  default     = {}
}
