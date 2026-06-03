# =============================================================================
# Compute module outputs
# =============================================================================

output "autoscaling_group_arn" {
  description = "Auto Scaling Group ARN, used by the ARC Region Switch Plan to scale capacity."
  value       = aws_autoscaling_group.this.arn
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group name, used for CloudWatch references and scaling policies."
  value       = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  description = "Launch Template ID, useful for AMI updates and debugging."
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Latest available Launch Template version."
  value       = aws_launch_template.this.latest_version
}
