# =============================================================================
# DYNAMODB MODULE — main.tf
#
# Creates a DynamoDB table with PAY_PER_REQUEST (On-Demand) billing.
# No provisioned capacity = no minimum cost, you pay only for actual reads/writes.
# Ref: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadWriteCapacityMode.html
# =============================================================================

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST" # On-Demand — no reserved capacity cost
  hash_key     = var.hash_key
  range_key    = var.range_key

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  # Point-in-Time Recovery — disabled by default to save cost in dev/demo
  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  # Server-Side Encryption with AWS-owned KMS key — enabled by default, no extra charge
  server_side_encryption {
    enabled = var.server_side_encryption_enabled
  }

  tags = {
    Name = var.table_name
  }
}
