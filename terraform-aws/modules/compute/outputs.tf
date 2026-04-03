output "instance_ids" {
  description = "Instance IDs keyed by lab node."
  value = merge(
    { for k, v in aws_instance.this : k => v.id },
    { b1 = aws_instance.b1.id }
  )
}

output "private_ips" {
  description = "Private IPs keyed by lab node."
  value = merge(
    { for k, v in aws_instance.this : k => v.private_ip },
    { b1 = aws_network_interface.palo_mgmt.private_ip }
  )
}

output "public_ips" {
  description = "Public IPs keyed by lab node."
  value = merge(
    { for k, v in aws_instance.this : k => v.public_ip },
    { b1 = aws_eip.palo_untrust.public_ip }
  )
}

output "named_instances" {
  description = "Structured instance data for reporting and validation."
  value = merge(
    {
      for k, v in aws_instance.this :
      k => {
        id         = v.id
        name       = v.tags["Name"]
        private_ip = v.private_ip
        public_ip  = v.public_ip
      }
    },
    {
      b1 = {
        id         = aws_instance.b1.id
        name       = "lab-b1-paloalto"
        private_ip = aws_network_interface.palo_mgmt.private_ip
        public_ip  = aws_eip.palo_untrust.public_ip
      }
    }
  )
}

output "key_pair_name" {
  description = "EC2 key pair name used by the lab instances."
  value       = aws_key_pair.lab.key_name
}

output "palo_eni_ids" {
  description = "Palo Alto ENI IDs keyed by role."
  value = {
    untrust = aws_network_interface.palo_untrust.id
    trust   = aws_network_interface.palo_trust.id
    mgmt    = aws_network_interface.palo_mgmt.id
  }
}

output "palo_untrust_eip" {
  description = "Palo Alto UNTRUST ENI public EIP."
  value       = aws_eip.palo_untrust.public_ip
}

