# =============================================================================
# DYNAMODB MODULE — variables.tf
# =============================================================================

variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "hash_key" {
  description = "Attribute name to use as the partition (hash) key"
  type        = string
}

variable "range_key" {
  description = "Attribute name to use as the sort (range) key. Omit if not needed."
  type        = string
  default     = null
}

variable "attributes" {
  description = <<-EOT
    List of attribute definitions for the table.
    Only key attributes (hash_key, range_key, and GSI/LSI keys) need to be declared here.
    Type: S = String, N = Number, B = Binary
  EOT
  type = list(object({
    name = string
    type = string
  }))
}

variable "point_in_time_recovery_enabled" {
  description = "Enable Point-in-Time Recovery (PITR). Incurs additional cost — keep false for dev/demo."
  type        = bool
  default     = false
}

variable "server_side_encryption_enabled" {
  description = "Enable server-side encryption using AWS-owned KMS key (no extra cost)"
  type        = bool
  default     = true
}
