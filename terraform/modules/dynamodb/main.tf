# =============================================================================
# DYNAMODB MODULE — main.tf  (Fase 2: Global Table v2 con réplica en Irlanda)
#
# Global Tables v2 (2019+, también llamado "versión actual"):
#   - Activo-Activo: ambas regiones pueden leer Y escribir simultáneamente.
#   - DynamoDB resuelve conflictos usando "last writer wins" por timestamp.
#   - Requiere: billing_mode = PAY_PER_REQUEST (ya configurado) y streams.
#   - La réplica se añade vía bloque `replica {}` dentro del recurso principal.
# =============================================================================

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST" # On-Demand — sin capacidad reservada mínima
  hash_key     = var.hash_key
  range_key    = var.range_key

  # DynamoDB Streams — OBLIGATORIO para Global Tables.
  # NEW_AND_OLD_IMAGES permite a la réplica reproducir inserciones,
  # actualizaciones y borrados con el estado anterior y posterior del ítem.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  # Point-in-Time Recovery — desactivado por defecto para ahorrar coste en demo
  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  # Cifrado en reposo con KMS gestionado por AWS — sin coste extra
  server_side_encryption {
    enabled = var.server_side_encryption_enabled
  }

  # ── Réplicas de Global Table ───────────────────────────────────────────────
  # Bloque dinámico por cada región de réplica declarada en var.replica_regions.
  # Al activar una réplica en eu-west-1, DynamoDB replicará todos los ítems
  # existentes y futuras escrituras en tiempo real (latencia típica < 1 s).
  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region_name = replica.value
    }
  }

  tags = {
    Name = var.table_name
  }

  # Nota de ciclo de vida:
  # La eliminación de una réplica (quitar de replica_regions) puede tardar
  # varios minutos. Terraform esperará a que DynamoDB confirme la eliminación.
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
