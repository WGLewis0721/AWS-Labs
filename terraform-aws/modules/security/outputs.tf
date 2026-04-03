output "default_security_group_ids" {
  description = "Default security groups after their rules have been stripped."
  value       = { for k, v in aws_default_security_group.this : k => v.id }
}

output "security_group_ids" {
  description = "Security group IDs keyed by lab role."
  value = {
    a_linux       = aws_security_group.a_linux.id
    a_windows     = aws_security_group.a_windows.id
    palo_untrust  = aws_security_group.palo_untrust.id
    palo_trust    = aws_security_group.palo_trust.id
    palo_mgmt     = aws_security_group.palo_mgmt.id
    c1_portal     = aws_security_group.c1_portal.id
    c2_gateway    = aws_security_group.c2_gateway.id
    c3_controller = aws_security_group.c3_controller.id
    d             = aws_security_group.d.id
  }
}
