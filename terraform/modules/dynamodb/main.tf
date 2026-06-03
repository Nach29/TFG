# =============================================================================
# DynamoDB module
#
# Global Tables v2 (2019+, also called the "current version"):
#   - Active-active: both regions can read and write simultaneously.
#   - DynamoDB resuelve conflictos usando "last writer wins" por timestamp.
#   - Requiere: billing_mode = PAY_PER_REQUEST (ya configurado) y streams.
#   - The replica is added through a `replica {}` block inside the main resource.
# =============================================================================

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST" # On-Demand; sin capacidad reservada minima
  hash_key     = var.hash_key
  range_key    = var.range_key

  # DynamoDB Streams: required for Global Tables.
  # NEW_AND_OLD_IMAGES allows the replica to replay inserts, updates, and deletes
  # with the previous and new item state.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  # Point-in-Time Recovery: disabled by default to save cost in demo environments.
  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  # At-rest encryption with AWS-managed KMS; no extra cost.
  server_side_encryption {
    enabled = var.server_side_encryption_enabled
  }

  # Global Table replicas.
  # Dynamic block for each replica region declared in var.replica_regions.
  # When a replica is enabled in eu-west-1, DynamoDB replicates all existing
  # items and future writes in real time (typical latency < 1 s).
  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region_name = replica.value
    }
  }

  tags = {
    Name = var.table_name
  }

  # Lifecycle note:
  # Removing a replica (by taking it out of replica_regions) can take several
  # minutes. Terraform waits until DynamoDB confirms the deletion.
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
