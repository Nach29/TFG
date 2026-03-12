# =============================================================================
# IAM MODULE — outputs.tf
# =============================================================================

output "role_arn" {
  description = "ARN of the IAM Role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IAM Role"
  value       = aws_iam_role.this.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM Instance Profile (used in EC2 launch)"
  value       = aws_iam_instance_profile.this.arn
}

output "instance_profile_name" {
  description = "Name of the IAM Instance Profile (used in EC2 launch)"
  value       = aws_iam_instance_profile.this.name
}
