# =============================================================================
# ALB module
#
# Supports two usage modes:
#   - Internet-facing (internal=false): public ALB for end clients.
#     enable_cross_zone_load_balancing=true, enable_zonal_shift=true
#   - Internal (internal=true): internal ALB in front of the App tier.
#     enable_cross_zone_load_balancing=false (critical for the Zonal Shift experiment)
#     enable_zonal_shift=false (no aplica en ALBs internos)
# =============================================================================

# ------- Application Load Balancer -------
resource "aws_lb" "main_alb" {
  name               = var.name
  internal           = var.internal
  load_balancer_type = "application"

  security_groups = var.security_group_ids
  subnets         = var.subnet_ids

  # Drop malformed HTTP headers; prevents HTTP desync attacks.
  drop_invalid_header_fields = var.drop_invalid_header_fields

  # Cross-zone load balancing:
  #   - true  on public ALBs (even traffic distribution across AZs)
  #   - false on Internal ALBs (required for the Zonal Shift experiment:
  #           if enabled, traffic can "escape" the affected AZ and the shift
  #           does not produce the observable effect this project demonstrates)
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # ARC Zonal Shift: allows traffic to be shifted away from a damaged AZ.
  # It only makes sense on public ALBs (internet-facing).
  # Requiere AWS provider >= 5.31.
  enable_zonal_shift = var.enable_zonal_shift

  # Disabled to simplify teardown of the PoC environment.
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

# ------- Listener HTTP:80 -> forward al Target Group -------
resource "aws_lb_listener" "http_forward" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = var.tg_port
  protocol          = var.tg_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# =============================================================================
# Required providers: allows the root module to pass provider aliases.
# Ref: https://developer.hashicorp.com/terraform/language/modules/develop/providers
# =============================================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.31, < 7.0"
    }
  }
}
