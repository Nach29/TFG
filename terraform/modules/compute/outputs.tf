# =============================================================================
# COMPUTE MODULE — outputs.tf
# =============================================================================

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.this.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.this.arn
}

output "private_ip" {
  description = "Primary private IP address of the instance"
  value       = aws_instance.this.private_ip
}

output "availability_zone" {
  description = "Availability Zone in which the instance was deployed"
  value       = aws_instance.this.availability_zone
}
