output "security_group_id" {
  description = "The ID of the created Security Group"
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  description = "The ARN of the Security Group"
  value       = aws_security_group.this.arn
}

output "security_group_name" {
  description = "The name of the Security Group"
  value       = aws_security_group.this.name
}