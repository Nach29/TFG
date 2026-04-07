# =============================================================================
# ARC VALIDATION LAMBDA MODULE — variables.tf
# =============================================================================

variable "name_prefix" {
  description = "Prefijo para todos los recursos del módulo (e.g. 'tfg-student-icolasma-TFG')"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Nombre de la DynamoDB Global Table cuya replicación se valida"
  type        = string
}

variable "target_region" {
  description = "Región de destino del Region Switch, usada como ReceivingRegion en la métrica CloudWatch (e.g. 'eu-west-1')"
  type        = string
  default     = "eu-west-1"
}

variable "max_latency_ms" {
  description = "Umbral máximo de ReplicationLatency en milisegundos. Si se supera, el Region Switch se detiene."
  type        = number
  default     = 2000
}

variable "log_retention_days" {
  description = "Días de retención del Log Group de CloudWatch para la Lambda"
  type        = number
  default     = 14
}

variable "account_id" {
  description = "ID de la cuenta AWS actual (data.aws_caller_identity.current.account_id) — usado para el resource policy de la Lambda"
  type        = string
}
