output "instance_ids" {
  description = "Instance IDs keyed by lab node."
  value       = { for key, value in aws_instance.this : key => value.id }
}

output "private_ips" {
  description = "Private IPs keyed by lab node."
  value       = { for key, value in aws_instance.this : key => value.private_ip }
}

output "public_ips" {
  description = "Public IPs keyed by lab node."
  value       = { for key, value in aws_instance.this : key => value.public_ip }
}

output "named_instances" {
  description = "Structured instance data for reporting and validation."
  value = {
    for key, value in aws_instance.this :
    key => {
      id         = value.id
      name       = value.tags["Name"]
      private_ip = value.private_ip
      public_ip  = value.public_ip
    }
  }
}

output "key_pair_name" {
  description = "EC2 key pair name used by the lab instances."
  value       = aws_key_pair.lab.key_name
}
