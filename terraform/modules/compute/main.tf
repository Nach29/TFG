# =============================================================================
# COMPUTE MODULE — main.tf  (Fase 2: refactorizado a ASG + Launch Template)
#
# Sustituye aws_instance por:
#   aws_launch_template  → define la configuración de las instancias
#   aws_autoscaling_group → gestiona el ciclo de vida y la capacidad
#
# Ventajas del cambio:
#   - desired_capacity configurable por región (3 activa, 1 standby)
#   - Auto-registro en Target Groups via var.target_group_arns
#   - Elasticidad automática ante fallos de instancia
#   - Compatible con ARC Region Switch (el plan puede modificar desired_capacity)
#
# Seguridad (se mantienen todos los hardening de Fase 1):
#   - IMDSv2 obligatorio (http_tokens = "required")
#   - EBS raíz cifrado
#   - Sin SSH (acceso únicamente vía SSM Session Manager)
# =============================================================================

# ── Launch Template ───────────────────────────────────────────────────────────
# Define la plantilla que el ASG usa para lanzar cada instancia.
# Equivale al antiguo aws_instance pero desacoplado de la gestión de capacidad.
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  description   = "Launch template for ${var.name_prefix} ASG"

  # User data: el caller pasa la cadena ya renderizada con templatefile()
  user_data = var.user_data != null ? base64encode(var.user_data) : null

  # Perfil IAM — SSM + permisos de la capa (web/app)
  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  # Security Groups
  vpc_security_group_ids = var.security_group_ids

  # Enforce IMDSv2 — previene ataques SSRF de robo de credenciales
  # Ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # EBS raíz — cifrado en reposo, sin coste adicional en gp3
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = var.root_volume_type
      volume_size           = var.root_volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Tag propagation — las instancias lanzadas heredan estos tags
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.common_tags,
      { Name = var.name_prefix },
      var.additional_tags
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      var.common_tags,
      { Name = "${var.name_prefix}-vol" },
      var.additional_tags
    )
  }

  tags = merge(
    var.common_tags,
    { Name = "${var.name_prefix}-lt" },
    var.additional_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────
# Gestiona la capacidad y el ciclo de vida de las instancias.
# Se registra automáticamente en el/los target groups configurados.
resource "aws_autoscaling_group" "this" {
  name_prefix = "${var.name_prefix}-asg-"

  # Distribución multi-AZ — una subnet privada por AZ
  vpc_zone_identifier = var.subnet_ids

  desired_capacity = var.desired_capacity
  min_size         = var.min_size
  max_size         = var.max_size

  # Registro automático en los ALB Target Groups indicados
  target_group_arns = var.target_group_arns

  # Health check vía ELB (más preciso que EC2) para sustituir instancias
  # que fallen el health check del ALB, no solo las que fallen a nivel de EC2.
  health_check_type         = "ELB"
  health_check_grace_period = 120 # segundos — da tiempo a que el user_data arranque

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # Estrategia de refresco de instancias — sustituye instancias gradualmente
  # cuando cambia el Launch Template (e.g., nuevo AMI / user_data).
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = var.name_prefix
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  dynamic "tag" {
    for_each = var.additional_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    # Ignorar cambios de desired_capacity realizados por ARC Region Switch Plan
    # o por políticas de escalado automático durante la operación normal.
    ignore_changes = [desired_capacity]
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
