output "default_security_group_ids" {
  description = "Default security groups after their rules have been stripped."
  value       = { for key, value in aws_default_security_group.this : key => value.id }
}

output "security_group_ids" {
  description = "Security group IDs keyed by lab role."
  value = {
    a_linux   = aws_security_group.a_linux.id
    a_windows = aws_security_group.a_windows.id
    b         = aws_security_group.b.id
    c         = aws_security_group.c.id
    d         = aws_security_group.d.id
  }
}
