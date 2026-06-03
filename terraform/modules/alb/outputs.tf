# ==========================================
# outputs.tf - Outputs for ALB Module
# Phase 2: added alb_zone_id for Route53 ALIAS records.
# ==========================================

output "alb_arn" {
  description = "Application Load Balancer ARN."
  value       = aws_lb.main_alb.arn
}

output "alb_dns_name" {
  description = "DNS name assigned by AWS to the ALB. Use it to create CNAME or ALIAS records in Route53."
  value       = aws_lb.main_alb.dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID, required for Route53 ALIAS records (aws_route53_record.alias.zone_id)."
  value       = aws_lb.main_alb.zone_id
}

output "target_group_arn" {
  description = "Target Group ARN. Passed to ASG target_group_arns or to the ALB listener."
  value       = aws_lb_target_group.ecs_tg.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (e.g. 'app/my-alb/1234567890abcdef'). Used as the LoadBalancer dimension in CloudWatch Alarms."
  value       = aws_lb.main_alb.arn_suffix
}
