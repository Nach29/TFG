# =============================================================================
# PROVIDERS
#
# Fase 2: Se añade un provider alias para eu-west-1 (Irlanda) para gestionar
# la infraestructura de Warm Standby y el ARC Region Switch Plan.
# La versión mínima del provider se actualiza a ~> 5.90 para incluir soporte
# nativo de aws_arcregionswitch_plan (disponible desde ~Feb 2026).
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.38" # v6 requerido para aws_arcregionswitch_plan nativo (ARC Region Switch)
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# ── Provider Principal: eu-central-1 (Fráncfort — Región Activa) ──────────────
provider "aws" {
  region = var.aws_region

  # default_tags se fusionan automáticamente en todos los recursos gestionados
  # por este provider, eliminando la necesidad de repetirlos en cada módulo.
  # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags
  default_tags {
    tags = {
      Project   = "TFG"
      Owner     = "student-icolasma"
      ManagedBy = "Terraform"
      Phase     = "2-DR"
    }
  }
}

# ── Provider Alias: eu-west-1 (Irlanda — Warm Standby / DR) ──────────────────
# Todos los recursos de Irlanda deben incluir: provider = aws.ireland
# El alias hereda el mismo conjunto de default_tags para consistencia.
provider "aws" {
  alias  = "ireland"
  region = var.dr_region

  default_tags {
    tags = {
      Project   = "TFG"
      Owner     = "student-icolasma"
      ManagedBy = "Terraform"
      Phase     = "2-DR"
      Role      = "WarmStandby"
    }
  }
}
