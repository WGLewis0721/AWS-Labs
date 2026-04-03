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

  From A2:
  ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@${module.compute.private_ips["b1"]}
  ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@${module.compute.private_ips["c1"]}
  ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@${module.compute.private_ips["d1"]}
  curl -s --connect-timeout 5 -o /dev/null -w "%%{http_code}" http://${module.compute.private_ips["b1"]}
  curl -s --connect-timeout 5 -o /dev/null -w "%%{http_code}" http://${module.compute.private_ips["c1"]}
  curl -s --connect-timeout 5 -o /dev/null -w "%%{http_code}" http://${module.compute.private_ips["d1"]}
  ping -c 3 ${module.compute.private_ips["b1"]}
  ping -c 3 ${module.compute.private_ips["c1"]}
  ping -c 3 ${module.compute.private_ips["d1"]}

  From B1:
  ssh -o ConnectTimeout=5 -i tgw-lab-key.pem ec2-user@${module.compute.private_ips["d1"]}
  ping -c 3 ${module.compute.private_ips["d1"]}

  From D1:
  curl -s --connect-timeout 5 -o /dev/null -w "%%{http_code}" http://${module.compute.private_ips["b1"]}
  curl -s --connect-timeout 5 -o /dev/null -w "%%{http_code}" http://${module.compute.private_ips["c1"]}
  curl -s --connect-timeout 5 -o /dev/null -w "%%{http_code}" http://${module.compute.private_ips["a2"]}

  From A1 Chrome:
  http://${module.compute.private_ips["b1"]}
  http://${module.compute.private_ips["c1"]}
  http://${module.compute.private_ips["d1"]}
  EOT
}
