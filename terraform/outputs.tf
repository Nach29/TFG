# =============================================================================
# Root outputs
# =============================================================================

# Networking
output "vpc_id_frankfurt" {
  description = "Frankfurt VPC ID (active region)."
  value       = module.vpc.vpc_id
}

output "vpc_id_ireland" {
  description = "Ireland VPC ID (warm standby region)."
  value       = module.vpc_ireland.vpc_id
}

# Public ALBs
output "alb_dns_name_frankfurt" {
  description = "Frankfurt public ALB DNS name."
  value       = module.alb.alb_dns_name
}

output "alb_dns_name_ireland" {
  description = "Ireland public ALB DNS name."
  value       = module.alb_ireland.alb_dns_name
}

output "alb_arn_frankfurt" {
  description = "Frankfurt public ALB ARN."
  value       = module.alb.alb_arn
}

# Internal ALBs
output "internal_alb_dns_frankfurt" {
  description = "Frankfurt internal ALB DNS name."
  value       = module.internal_alb.alb_dns_name
}

output "internal_alb_dns_ireland" {
  description = "Ireland internal ALB DNS name."
  value       = module.internal_alb_ireland.alb_dns_name
}

# Auto Scaling Groups
output "web_asg_name_frankfurt" {
  description = "Frankfurt Web ASG name."
  value       = module.web_asg.autoscaling_group_name
}

output "app_asg_name_frankfurt" {
  description = "Frankfurt App ASG name."
  value       = module.app_asg.autoscaling_group_name
}

output "web_asg_arn_ireland" {
  description = "Ireland Web ASG ARN."
  value       = module.web_asg_ireland.autoscaling_group_arn
}

output "app_asg_arn_ireland" {
  description = "Ireland App ASG ARN."
  value       = module.app_asg_ireland.autoscaling_group_arn
}

# DynamoDB
output "dynamodb_table_name" {
  description = "DynamoDB Global Table name."
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "DynamoDB Global Table ARN in the primary region."
  value       = module.dynamodb.table_arn
}

# Route 53
output "domain_name" {
  description = "Service URL published through Route 53 failover."
  value       = "http://${var.domain_name}"
}


# ARC
output "arc_dr_plan_name" {
  description = "ARC Region Switch Plan name."
  value       = aws_arcregionswitch_plan.main_dr_plan.name
}

output "arc_dr_plan_arn" {
  description = "ARC Region Switch Plan ARN."
  value       = aws_arcregionswitch_plan.main_dr_plan.arn
}

# IAM
output "web_iam_instance_profile_frankfurt" {
  description = "Frankfurt Web instance profile name."
  value       = module.iam_web.instance_profile_name
}

output "app_iam_instance_profile_frankfurt" {
  description = "Frankfurt App instance profile name."
  value       = module.iam_app.instance_profile_name
}
