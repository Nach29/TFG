# =============================================================================
# ALB MODULE — main.tf  (Fase 2: parametriza internal, cross_zone, zonal_shift)
#
# Soporta dos modos de uso:
#   - Internet-facing (internal=false): ALB público para clientes finales.
#     enable_cross_zone_load_balancing=true, enable_zonal_shift=true
#   - Internal (internal=true): ALB interno delante de la capa App.
#     enable_cross_zone_load_balancing=false (CRÍTICO para Zonal Shift experimento)
#     enable_zonal_shift=false (no aplica en ALBs internos)
# =============================================================================

# ------- Application Load Balancer -------
resource "aws_lb" "main_alb" {
  name               = var.name
  internal           = var.internal
  load_balancer_type = "application"

  security_groups = var.security_group_ids
  subnets         = var.subnet_ids

  # Descartar cabeceras HTTP malformadas — previene ataques HTTP desync
  drop_invalid_header_fields = var.drop_invalid_header_fields

  # Cross-zone load balancing:
  #   - true  en ALBs públicos (distribución homogénea de tráfico entre AZs)
  #   - false en Internal ALBs (OBLIGATORIO para el experimento de Zonal Shift:
  #           si está activo, el tráfico "escapa" de la AZ afectada y el shift
  #           no produce el efecto observable que se quiere demostrar)
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # ARC Zonal Shift — permite desplazar tráfico fuera de una AZ dañada.
  # Solo tiene sentido en ALBs públicos (internet-facing).
  # Requiere AWS provider >= 5.31.
  enable_zonal_shift = var.enable_zonal_shift

  # Deshabilitado para facilitar el teardown del entorno de PoC
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

# ------- Listener HTTP:80 → forward al Target Group -------
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
# Required providers — permite que el root pase provider aliases (e.g. aws.ireland)
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
