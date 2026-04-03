output "availability_zone" {
  description = "Availability zone used by the lab subnets."
  value       = local.selected_az
}

output "vpc_ids" {
  description = "VPC IDs keyed by lab segment."
  value       = { for key, value in aws_vpc.this : key => value.id }
}

output "vpc_cidrs" {
  description = "CIDR blocks keyed by lab segment."
  value       = { for key, value in local.vpcs : key => value.cidr }
}

output "subnet_ids" {
  description = "Subnet IDs keyed by lab segment."
  value       = { for key, value in aws_subnet.this : key => value.id }
}

output "subnet_cidrs" {
  description = "Subnet CIDR blocks keyed by lab segment."
  value       = { for key, value in local.subnets : key => value.cidr }
}

output "route_table_ids" {
  description = "Custom route table IDs keyed by lab segment."
  value       = { for key, value in aws_route_table.this : key => value.id }
}

output "network_acl_ids" {
  description = "Network ACL IDs keyed by lab segment."
  value       = { for key, value in aws_network_acl.this : key => value.id }
}

output "transit_gateway_ids" {
  description = "Transit Gateway IDs keyed by TGW name."
  value       = { for key, value in aws_ec2_transit_gateway.this : key => value.id }
}

output "transit_gateway_route_table_ids" {
  description = "Transit Gateway route table IDs keyed by TGW name."
  value       = { for key, value in aws_ec2_transit_gateway_route_table.this : key => value.id }
}

output "transit_gateway_attachment_ids" {
  description = "Transit Gateway VPC attachment IDs keyed by attachment name."
  value       = { for key, value in aws_ec2_transit_gateway_vpc_attachment.this : key => value.id }
}
