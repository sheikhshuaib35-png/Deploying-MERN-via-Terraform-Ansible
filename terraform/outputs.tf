output "web_public_ip" {
  description = "Public IPv4 address of the web server."
  value       = aws_instance.web.public_ip
}

output "web_availability_zone" {
  description = "Availability Zone containing the web and database subnets."
  value       = aws_instance.web.availability_zone
}

output "web_public_dns" {
  description = "Public DNS name of the web server."
  value       = aws_instance.web.public_dns
}

output "web_instance_id" {
  description = "Instance ID of the public web server."
  value       = aws_instance.web.id
}

output "database_private_ip" {
  description = "Private IPv4 address of the MongoDB server."
  value       = aws_instance.database.private_ip
}

output "database_instance_id" {
  description = "Instance ID of the private MongoDB server."
  value       = aws_instance.database.id
}

output "vpc_id" {
  description = "ID of the project VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public web subnet."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private database subnet."
  value       = aws_subnet.private.id
}

output "nat_gateway_public_ip" {
  description = "Elastic IP used by the private subnet's NAT Gateway."
  value       = aws_eip.nat.public_ip
}

output "application_url" {
  description = "HTTP URL of the public web server after Ansible deployment."
  value       = "http://${aws_instance.web.public_ip}"
}

output "ssh_web_command" {
  description = "SSH command for connecting to the web host from the Ansible control machine."
  value       = "ssh -i <private-key-path> ubuntu@${aws_instance.web.public_ip}"
}
