# FILE: outputs.tf

output "vpc_id" {
  description = "The ID of the created VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "A list of the private subnet IDs where worker nodes will be placed."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "public_subnet_ids" {
  description = "A list of the public subnet IDs for internet-facing load balancers."
  value       = [for subnet in aws_subnet.public : subnet.id]
}
