# =============================================================================
# DynamoDB module variables
# =============================================================================

variable "table_name" {
  description = "DynamoDB table name."
  type        = string
}

variable "hash_key" {
  description = "Attribute name to use as the partition (hash) key."
  type        = string
}

variable "range_key" {
  description = "Attribute name to use as the sort (range) key. Omit if not needed."
  type        = string
  default     = null
}

variable "attributes" {
  description = <<-EOT
    List of table attribute definitions.
    Only key attributes (hash_key, range_key, and GSI/LSI keys) must be declared here.
    Type: S = String, N = Number, B = Binary
  EOT
  type = list(object({
    name = string
    type = string
  }))
}

variable "point_in_time_recovery_enabled" {
  description = "Enable Point-in-Time Recovery (PITR). Adds cost; disabled by default in dev/demo."
  type        = bool
  default     = false
}

variable "server_side_encryption_enabled" {
  description = "Enable at-rest encryption with AWS-managed KMS (no extra cost)."
  type        = bool
  default     = true
}

variable "replica_regions" {
  description = <<-EOT
    List of AWS regions where Global Table v2 replicas are deployed.
    Ejemplo: ["eu-west-1"]
    Empty list = local table with no replicas (Phase 1).
    IMPORTANT: the table must have stream_enabled = true (enabled in main.tf).
  EOT
  type        = list(string)
  default     = []
}
