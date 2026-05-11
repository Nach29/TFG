# =============================================================================
# Root outputs
# =============================================================================

# Networking
output "vpc_id_frankfurt" {
  description = "ID del VPC de Frankfurt (region activa)"
  value       = module.vpc.vpc_id
}

output "vpc_id_ireland" {
  description = "ID del VPC de Irlanda (warm standby)"
  value       = module.vpc_ireland.vpc_id
}

# Public ALBs
output "alb_dns_name_frankfurt" {
  description = "DNS del ALB publico de Frankfurt"
  value       = module.alb.alb_dns_name
}

output "alb_dns_name_ireland" {
  description = "DNS del ALB publico de Irlanda"
  value       = module.alb_ireland.alb_dns_name
}

output "alb_arn_frankfurt" {
  description = "ARN del ALB publico de Frankfurt"
  value       = module.alb.alb_arn
}

# Internal ALBs
output "internal_alb_dns_frankfurt" {
  description = "DNS del Internal ALB de Frankfurt"
  value       = module.internal_alb.alb_dns_name
}

output "internal_alb_dns_ireland" {
  description = "DNS del Internal ALB de Irlanda"
  value       = module.internal_alb_ireland.alb_dns_name
}

# Auto Scaling Groups
output "web_asg_name_frankfurt" {
  description = "Nombre del ASG Web de Frankfurt"
  value       = module.web_asg.autoscaling_group_name
}

output "app_asg_name_frankfurt" {
  description = "Nombre del ASG App de Frankfurt"
  value       = module.app_asg.autoscaling_group_name
}

output "web_asg_arn_ireland" {
  description = "ARN del ASG Web de Irlanda"
  value       = module.web_asg_ireland.autoscaling_group_arn
}

output "app_asg_arn_ireland" {
  description = "ARN del ASG App de Irlanda"
  value       = module.app_asg_ireland.autoscaling_group_arn
}

# DynamoDB
output "dynamodb_table_name" {
  description = "Nombre de la DynamoDB Global Table"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "ARN de la DynamoDB Global Table en la region primaria"
  value       = module.dynamodb.table_arn
}

# Route 53
output "domain_name" {
  description = "URL del servicio publicada mediante Route 53 failover"
  value       = "http://${var.domain_name}"
}


# ARC
output "arc_dr_plan_name" {
  description = "Nombre del ARC Region Switch Plan"
  value       = aws_arcregionswitch_plan.main_dr_plan.name
}

output "arc_dr_plan_arn" {
  description = "ARN del ARC Region Switch Plan"
  value       = aws_arcregionswitch_plan.main_dr_plan.arn
}

# IAM
output "web_iam_instance_profile_frankfurt" {
  description = "Nombre del instance profile Web de Frankfurt"
  value       = module.iam_web.instance_profile_name
}

output "app_iam_instance_profile_frankfurt" {
  description = "Nombre del instance profile App de Frankfurt"
  value       = module.iam_app.instance_profile_name
}
