# =============================================================================
# ALB MODULE — main.tf
#
# Internet-facing Application Load Balancer for the PoC.
# HTTP only (port 80) — no TLS/ACM required.
# ARC Zonal Shift enabled for resilience testing.
# =============================================================================

# ------- Application Load Balancer -------
resource "aws_lb" "main_alb" {
  name               = var.name
  internal           = false
  load_balancer_type = "application"

  security_groups = var.security_group_ids
  subnets         = var.subnet_ids

  # Drop malformed HTTP headers — prevents HTTP desync attacks
  drop_invalid_header_fields = var.drop_invalid_header_fields

  # Cross-zone load balancing — always on for ALBs, declared explicitly for clarity
  enable_cross_zone_load_balancing = true

  # ARC Zonal Shift — allows Route 53 ARC to shift traffic away from an
  # impaired AZ at the load balancer level. Requires AWS provider >= 5.31.
  enable_zonal_shift = true

  # Intentionally disabled for PoC teardown ease
  # enable_deletion_protection = true

  tags = var.tags_lb
}

# ------- Target Group -------
resource "aws_lb_target_group" "ecs_tg" {
  name                 = "${var.name}-tg"
  port                 = var.tg_port
  protocol             = var.tg_protocol
  vpc_id               = var.vpc_id
  target_type          = var.tg_target_type
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.hc_path
    interval            = var.hc_interval
    timeout             = var.hc_timeout
    healthy_threshold   = var.hc_healthy_threshold
    unhealthy_threshold = var.hc_unhealthy_threshold
    protocol            = var.tg_protocol
    matcher             = var.hc_matcher
  }

  tags = var.tags_tg
}

# ------- Listener HTTP:80 → forward to Target Group -------
resource "aws_lb_listener" "http_forward" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}
