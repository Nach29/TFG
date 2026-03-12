# =============================================================================
# AUTO-RECOVERY MODULE — outputs.tf
# =============================================================================

output "lambda_function_arn" {
  description = "ARN of the ARC Zonal Shift auto-recovery Lambda function."
  value       = aws_lambda_function.zonal_shift.arn
}

output "lambda_function_name" {
  description = "Name of the auto-recovery Lambda function."
  value       = aws_lambda_function.zonal_shift.function_name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role attached to the auto-recovery Lambda."
  value       = aws_iam_role.lambda_exec.arn
}

output "cloudwatch_alarm_arns" {
  description = "Map of AZ to CloudWatch Alarm ARN for each per-AZ 5XX alarm."
  value = {
    for az, alarm in aws_cloudwatch_metric_alarm.alb_5xx_per_az : az => alarm.arn
  }
}

output "log_group_name" {
  description = "CloudWatch Log Group name for the auto-recovery Lambda."
  value       = aws_cloudwatch_log_group.lambda_logs.name
}
