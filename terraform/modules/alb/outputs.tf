# ==========================================
# outputs.tf - Outputs for ALB Module
# ==========================================

output "alb_arn" {
  description = "The ARN of the Application Load Balancer. Useful for integrations such as WAF."
  value       = aws_lb.main_alb.arn
}

output "alb_dns_name" {
  description = "The DNS name (URL) assigned by AWS for the ALB. Use this to create a CNAME or ALIAS record in Route53."
  value       = aws_lb.main_alb.dns_name
}

output "target_group_arn" {
  description = "The ARN of the Target Group. Required to inject into the 'load_balancer' block of an 'aws_ecs_service' resource."
  value       = aws_lb_target_group.ecs_tg.arn
}

output "alb_arn_suffix" {
  description = "The ARN suffix of the ALB (e.g. 'app/my-alb/1234567890abcdef'). Used as the LoadBalancer dimension value in CloudWatch Alarms — CloudWatch uses the suffix, not the full ARN."
  value       = aws_lb.main_alb.arn_suffix
}
