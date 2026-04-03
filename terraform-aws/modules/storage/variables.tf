variable "name_prefix" {
  type        = string
  description = "Prefix used for naming storage resources."
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to storage resources."
  default     = {}
}
