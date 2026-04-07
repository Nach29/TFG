# ==========================================
# outputs.tf - Outputs for ALB Module
# Fase 2: añadido alb_zone_id para registros Route53 ALIAS
# ==========================================

output "alb_arn" {
  description = "ARN del Application Load Balancer."
  value       = aws_lb.main_alb.arn
}

output "alb_dns_name" {
  description = "DNS name asignado por AWS al ALB. Úsalo para crear registros CNAME o ALIAS en Route53."
  value       = aws_lb.main_alb.dns_name
}

output "alb_zone_id" {
  description = "Zone ID del ALB — requerido para registros Route53 ALIAS (aws_route53_record.alias.zone_id)"
  value       = aws_lb.main_alb.zone_id
}

output "target_group_arn" {
  description = "ARN del Target Group. Pasado a target_group_arns del ASG o al listener del ALB."
  value       = aws_lb_target_group.ecs_tg.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix del ALB (e.g. 'app/my-alb/1234567890abcdef'). Usado como dimensión LoadBalancer en CloudWatch Alarms."
  value       = aws_lb.main_alb.arn_suffix
}
