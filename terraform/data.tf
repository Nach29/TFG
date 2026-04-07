# =============================================================================
# DATA SOURCES
#
# Fase 1: AMI AL2023 en eu-central-1 via SSM Parameter Store
# Fase 2: AMI AL2023 en eu-west-1 (Irlanda), Hosted Zone Route53, identidad
# =============================================================================

# ── AMI — eu-central-1 (Fráncfort, Región Activa) ────────────────────────────
# Parámetro público mantenido por AWS — siempre apunta a la última AMI AL2023
# para arquitectura x86_64 en la región configurada.
data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ── AMI — eu-west-1 (Irlanda, Warm Standby) ───────────────────────────────────
# Mismo parámetro público pero consultado con el provider alias de Irlanda.
# Las AMIs son distintas por región, aunque el nombre del parámetro es idéntico.
data "aws_ssm_parameter" "amazon_linux_2023_ireland" {
  provider = aws.ireland
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ── Route 53 — Hosted Zone de dontpushthis.link ──────────────────────────────
# La Hosted Zone ya existe en la cuenta. Se recupera por nombre para evitar
# hardcodear el Zone ID (buena práctica — el ID cambia si la zona se recrea).
# Route 53 es global: no requiere provider alias.
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ── Identidad de la cuenta AWS actual ────────────────────────────────────────
# Necesario para construir ARNs de recursos en políticas IAM y para el
# execution_role del ARC Region Switch Plan.
data "aws_caller_identity" "current" {}

# ── Región actual ─────────────────────────────────────────────────────────────
data "aws_region" "current" {}
