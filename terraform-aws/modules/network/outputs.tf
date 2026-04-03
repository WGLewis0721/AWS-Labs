output "availability_zone" {
  description = "Availability zone used by the lab subnets."
  value       = local.selected_az
}

output "vpc_ids" {
  description = "VPC IDs keyed by lab segment."
  value       = { for k, v in aws_vpc.this : k => v.id }
}

output "vpc_cidrs" {
  description = "CIDR blocks keyed by lab segment."
  value       = { for k, v in local.vpcs : k => v.cidr }
}

output "subnet_ids" {
  description = "Subnet IDs keyed by subnet key."
  value       = { for k, v in aws_subnet.this : k => v.id }
}

output "subnet_cidrs" {
  description = "Subnet CIDR blocks keyed by subnet key."
  value       = { for k, v in local.subnets : k => v.cidr }
}

output "route_table_ids" {
  description = "Route table IDs keyed by subnet key."
  value       = { for k, v in aws_route_table.this : k => v.id }
}

output "network_acl_ids" {
  description = "Network ACL IDs keyed by subnet key."
  value       = { for k, v in aws_network_acl.this : k => v.id }
}

output "transit_gateway_ids" {
  description = "Transit Gateway IDs keyed by TGW name."
  value       = { for k, v in aws_ec2_transit_gateway.this : k => v.id }
}

output "transit_gateway_route_table_ids" {
  description = "Transit Gateway route table IDs keyed by TGW name."
  value       = { for k, v in aws_ec2_transit_gateway_route_table.this : k => v.id }
}

output "transit_gateway_attachment_ids" {
  description = "Transit Gateway VPC attachment IDs keyed by attachment name."
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}

output "nat_gateway_eip" {
  description = "Public IP address of the NAT Gateway EIP in VPC-A."
  value       = aws_eip.nat_gw.public_ip
}

output "alb_dns_name" {
  description = "DNS name of the internet-facing ALB (customer entry)."
  value       = aws_lb.alb.dns_name
}

output "nlb_b_dns_name" {
  description = "DNS name of the internal NLB in VPC-B (Palo Alto trust)."
  value       = aws_lb.nlb_b.dns_name
}

output "nlb_c_dns_name" {
  description = "DNS name of the internal NLB in VPC-C (AppGate portal)."
  value       = aws_lb.nlb_c.dns_name
}
