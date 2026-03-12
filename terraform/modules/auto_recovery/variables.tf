# =============================================================================
# AUTO-RECOVERY MODULE — variables.tf
#
# Input variables for the Closed-Loop ARC Zonal Shift auto-recovery system.
# =============================================================================

variable "project_prefix" {
  description = "Naming prefix applied to every resource in this module."
  type        = string
}

variable "alb_arn" {
  description = <<-EOT
    Full ARN of the Application Load Balancer that ARC Zonal Shift will act on.
    Used both as an environment variable for the Lambda function and as a
    CloudWatch Alarm dimension to scope metrics to this specific ALB.
  EOT
  type        = string
}

variable "alb_arn_suffix" {
  description = <<-EOT
    The ARN suffix of the ALB (e.g. "app/my-alb/1234567890abcdef").
    Used as the LoadBalancer dimension value in CloudWatch Alarms.
    Obtainable via: module.alb.alb_arn_suffix (aws_lb.arn_suffix attribute).
  EOT
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zones to create one CloudWatch Alarm per AZ."
  type        = list(string)
}

variable "alarm_5xx_threshold" {
  description = "Number of 5XX HTTP responses that triggers the alarm (sum over 1 minute)."
  type        = number
  default     = 10
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods before the alarm fires."
  type        = number
  default     = 1
}

variable "alarm_period_seconds" {
  description = "CloudWatch alarm period in seconds."
  type        = number
  default     = 60
}

variable "zonal_shift_expiry_minutes" {
  description = "Duration in minutes for the ARC Zonal Shift expiration window."
  type        = number
  default     = 30
}

variable "lambda_log_retention_days" {
  description = "Number of days to retain Lambda CloudWatch Logs."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Additional tags to apply to all resources in this module."
  type        = map(string)
  default     = {}
}
