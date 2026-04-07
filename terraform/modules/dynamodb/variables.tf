# =============================================================================
# DYNAMODB MODULE — variables.tf  (Fase 2: añade replica_regions)
# =============================================================================

variable "table_name" {
  description = "Nombre de la tabla DynamoDB"
  type        = string
}

variable "hash_key" {
  description = "Nombre del atributo a usar como partition (hash) key"
  type        = string
}

variable "range_key" {
  description = "Nombre del atributo a usar como sort (range) key. Omitir si no se necesita."
  type        = string
  default     = null
}

variable "attributes" {
  description = <<-EOT
    Lista de definiciones de atributos de la tabla.
    Solo los atributos key (hash_key, range_key y claves de GSI/LSI) deben declararse aquí.
    Tipo: S = String, N = Number, B = Binary
  EOT
  type = list(object({
    name = string
    type = string
  }))
}

variable "point_in_time_recovery_enabled" {
  description = "Habilitar Point-in-Time Recovery (PITR). Añade coste — desactivado por defecto en dev/demo."
  type        = bool
  default     = false
}

variable "server_side_encryption_enabled" {
  description = "Habilitar cifrado en reposo con KMS gestionado por AWS (sin coste extra)"
  type        = bool
  default     = true
}

variable "replica_regions" {
  description = <<-EOT
    Lista de regiones AWS donde desplegar réplicas de Global Table v2.
    Ejemplo: ["eu-west-1"]
    Lista vacía = tabla local sin réplicas (Fase 1).
    IMPORTANTE: la tabla debe tener stream_enabled = true (activado en main.tf).
  EOT
  type        = list(string)
  default     = []
}
