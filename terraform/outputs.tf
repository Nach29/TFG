# =============================================================================
# ROOT OUTPUTS — Fase 2
# =============================================================================

# ── VPC ───────────────────────────────────────────────────────────────────────
output "vpc_id_frankfurt" {
  description = "ID del VPC de Fráncfort (región activa)"
  value       = module.vpc.vpc_id
}

output "vpc_id_ireland" {
  description = "ID del VPC de Irlanda (warm standby)"
  value       = module.vpc_ireland.vpc_id
}

# ── ALBs Públicos ─────────────────────────────────────────────────────────────
output "alb_dns_name_frankfurt" {
  description = "DNS del ALB público de Fráncfort — endpoint de producción"
  value       = module.alb.alb_dns_name
}

output "alb_dns_name_ireland" {
  description = "DNS del ALB público de Irlanda — endpoint de failover"
  value       = module.alb_ireland.alb_dns_name
}

output "alb_arn_frankfurt" {
  description = "ARN del ALB de Fráncfort (para ARC Zonal Shift y CloudWatch)"
  value       = module.alb.alb_arn
}

# ── Internal ALBs ─────────────────────────────────────────────────────────────
output "internal_alb_dns_frankfurt" {
  description = "DNS del Internal ALB de Fráncfort (apuntado por el user_data de la capa Web)"
  value       = module.internal_alb.alb_dns_name
}

output "internal_alb_dns_ireland" {
  description = "DNS del Internal ALB de Irlanda"
  value       = module.internal_alb_ireland.alb_dns_name
}

# ── ASG ───────────────────────────────────────────────────────────────────────
output "web_asg_name_frankfurt" {
  description = "Nombre del ASG Web de Fráncfort"
  value       = module.web_asg.autoscaling_group_name
}

output "app_asg_name_frankfurt" {
  description = "Nombre del ASG App de Fráncfort"
  value       = module.app_asg.autoscaling_group_name
}

output "web_asg_arn_ireland" {
  description = "ARN del ASG Web de Irlanda — referenciado en el ARC Region Switch Plan"
  value       = module.web_asg_ireland.autoscaling_group_arn
}

output "app_asg_arn_ireland" {
  description = "ARN del ASG App de Irlanda — referenciado en el Paso 1 del ARC Plan"
  value       = module.app_asg_ireland.autoscaling_group_arn
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────
output "dynamodb_table_name" {
  description = "Nombre de la DynamoDB Global Table de sesiones"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "ARN de la DynamoDB Global Table (región primaria eu-central-1)"
  value       = module.dynamodb.table_arn
}

# ── Route 53 ──────────────────────────────────────────────────────────────────
output "domain_name" {
  description = "Nombre de dominio del servicio — apunta via Route53 Failover al ALB activo"
  value       = "http://${var.domain_name}"
}

output "route53_health_check_id" {
  description = "ID del Route53 Health Check de Fráncfort — referenciado en el ARC Region Switch Plan"
  value       = aws_route53_health_check.frankfurt_alb.id
}

# ── ARC ───────────────────────────────────────────────────────────────────────
output "arc_dr_plan_name" {
  description = "Nombre del ARC Region Switch Plan"
  value       = aws_arcregionswitch_plan.main_dr_plan.name
}

output "arc_dr_plan_arn" {
  description = "ARN del ARC Region Switch Plan — para ejecutarlo desde la consola o CLI"
  value       = aws_arcregionswitch_plan.main_dr_plan.arn
}

output "arc_validation_lambda_arn" {
  description = "ARN de la Lambda de validación DynamoDB del ARC Plan (Paso 2)"
  value       = module.arc_validation_lambda.lambda_arn
}

# ── IAM ───────────────────────────────────────────────────────────────────────
output "web_iam_instance_profile_frankfurt" {
  description = "Nombre del IAM Instance Profile Web de Fráncfort (SSM only)"
  value       = module.iam_web.instance_profile_name
}

output "app_iam_instance_profile_frankfurt" {
  description = "Nombre del IAM Instance Profile App de Fráncfort (SSM + DynamoDB)"
  value       = module.iam_app.instance_profile_name
}
