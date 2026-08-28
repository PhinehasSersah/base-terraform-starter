output "vpc_id" {
  description = "ID of the VPC."
  value       = var.existing_vpc_id
}

output "subnet_id" {
  description = "ID of the public subnet."
  value       = var.existing_subnet_id
}

output "security_group_id" {
  description = "ID of the web-tier security group."
  value       = aws_security_group.web.id
}
