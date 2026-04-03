output "environment" {
  description = "Environment name."
  value       = local.environment
}

output "availability_zone" {
  description = "Availability zone selected for the lab subnets."
  value       = module.network.availability_zone
}

output "name_prefix" {
  description = "Resource name prefix used in this environment."
  value       = local.name_prefix
}

output "common_tags" {
  description = "Resolved tag map applied across modules."
  value       = local.common_tags
}

output "instance_ids" {
  description = "Instance IDs keyed by lab node."
  value       = module.compute.instance_ids
}

output "private_ips" {
  description = "Private IPs keyed by lab node."
  value       = module.compute.private_ips
}

output "public_ips" {
  description = "Public IPs keyed by lab node."
  value       = module.compute.public_ips
}

output "a1_windows_public_ip" {
  description = "Public IP for the Windows browser host."
  value       = module.compute.public_ips["a1"]
}

output "a2_linux_public_ip" {
  description = "Public IP for the Linux jump host."
  value       = module.compute.public_ips["a2"]
}

output "palo_untrust_eip" {
  description = "Public EIP for Palo Alto UNTRUST ENI."
  value       = module.compute.palo_untrust_eip
}

output "nat_gateway_eip" {
  description = "Public EIP for the NAT Gateway (centralized egress)."
  value       = module.network.nat_gateway_eip
}

output "alb_dns_name" {
  description = "DNS name of the internet-facing ALB."
  value       = module.network.alb_dns_name
}

output "nlb_b_dns_name" {
  description = "DNS name of NLB-B (internal, Palo Alto trust)."
  value       = module.network.nlb_b_dns_name
}

output "nlb_c_dns_name" {
  description = "DNS name of NLB-C (internal, AppGate Portal)."
  value       = module.network.nlb_c_dns_name
}

output "key_pair_name" {
  description = "EC2 key pair name used by the lab."
  value       = module.compute.key_pair_name
}

output "validation_targets" {
  description = "Resource identifiers needed for post-apply AWS CLI validation."
  value = {
    network_acls                 = module.network.network_acl_ids
    route_tables                 = module.network.route_table_ids
    security_groups              = module.security.security_group_ids
    subnets                      = module.network.subnet_ids
    transit_gateway_attachments  = module.network.transit_gateway_attachment_ids
    transit_gateway_route_tables = module.network.transit_gateway_route_table_ids
    transit_gateways             = module.network.transit_gateway_ids
    vpcs                         = module.network.vpc_ids
    palo_eni_ids                 = module.compute.palo_eni_ids
  }
}

output "rdp_password_decrypt_command" {
  description = "AWS CLI command for retrieving the Windows Administrator password."
  value       = "aws ec2 get-password-data --instance-id ${module.compute.instance_ids["a1"]} --priv-launch-key tgw-lab-key.pem --query 'PasswordData' --output text --region ${var.aws_region}"
}

output "test_commands" {
  description = "Connectivity test matrix populated with the planned IP addresses."
  value       = <<-EOT
  SSH to A2:
  ssh -i tgw-lab-key.pem ec2-user@${module.compute.public_ips["a2"]}

  From A2 — Management path:
  ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@10.1.3.10   # Palo MGMT — MUST WORK
  curl -sk -o /dev/null -w "%%{http_code}" https://10.1.3.10       # Palo MGMT HTTPS
  curl -s  -o /dev/null -w "%%{http_code}" http://${module.network.nlb_b_dns_name}   # NLB-B HTTP — MUST WORK
  curl -sk -o /dev/null -w "%%{http_code}" https://${module.network.nlb_b_dns_name}  # NLB-B HTTPS
  curl -sk -o /dev/null -w "%%{http_code}" https://${module.network.nlb_c_dns_name}  # NLB-C — MUST WORK
  curl -sk -o /dev/null -w "%%{http_code}" https://10.2.4.10:8443  # Controller admin — MUST WORK
  curl -sk -o /dev/null -w "%%{http_code}" https://10.2.3.10       # Gateway — MUST WORK
  curl -s  --connect-timeout 5 -o /dev/null -w "%%{http_code}" http://10.3.1.10  # D1 — MUST FAIL

  From B1 MGMT ENI (SSH: A2 → 10.1.3.10) — centralized egress test:
  curl -s --connect-timeout 10 https://checkip.amazonaws.com
  # Expected: ${module.network.nat_gateway_eip}

  From c1-portal (SSH: A2 → 10.2.2.10):
  curl -sk -o /dev/null -w "%%{http_code}" https://10.2.3.10       # Gateway — MUST WORK
  curl -sk -o /dev/null -w "%%{http_code}" https://10.2.4.10:8443  # Controller — MUST WORK
  curl -s  --connect-timeout 10 https://checkip.amazonaws.com      # NAT GW egress

  From D1 (SSH: A2 → B1 TRUST 10.1.2.10 → D1 10.3.1.10):
  curl -sk -o /dev/null -w "%%{http_code}" https://${module.network.nlb_c_dns_name}  # Portal — MUST WORK
  curl -s  -o /dev/null -w "%%{http_code}" http://${module.network.nlb_b_dns_name}   # Palo — MUST WORK
  curl -sk --connect-timeout 5 https://10.2.4.10:8443              # Controller — MUST FAIL
  curl -s  --connect-timeout 5 http://10.0.1.10                    # VPC-A — MUST FAIL

  ALB (internet-facing):
  curl -sk -o /dev/null -w "%%{http_code}" https://${module.network.alb_dns_name}
  EOT
}

