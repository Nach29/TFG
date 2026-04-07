# =============================================================================
# ALB MODULE — variables.tf  (Fase 2: añade internal, cross_zone y zonal_shift)
# =============================================================================

# ------- General -------
variable "name" {
  type        = string
  description = "Nombre para el ALB y recursos derivados (TG, listener)."
}

variable "tags_lb" {
  type        = map(string)
  description = "Tags a aplicar al recurso ALB."
  default     = {}
}

variable "tags_tg" {
  type        = map(string)
  description = "Tags a aplicar al Target Group."
  default     = {}
}

# ------- Network -------
variable "vpc_id" {
  type        = string
  description = "ID del VPC donde se crea el Target Group."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Lista de IDs de subnets para el ALB (mínimo 2 AZs)."
}

variable "security_group_ids" {
  type        = list(string)
  description = "Lista de IDs de Security Groups a adjuntar al ALB."
}

# ------- ALB Settings -------
variable "internal" {
  type        = bool
  description = <<-EOT
    true  → ALB interno (no accesible desde internet) — usado para la capa App.
    false → ALB público (internet-facing) — usado por los clientes finales.
  EOT
  default     = false
}

variable "drop_invalid_header_fields" {
  type        = bool
  description = "Descartar cabeceras HTTP malformadas. Recomendado true para prevenir ataques HTTP desync."
  default     = true
}

variable "enable_cross_zone_load_balancing" {
  type        = bool
  description = <<-EOT
    Habilita el balanceo de carga entre zonas.
    CRÍTICO: Debe ser FALSE en el Internal ALB de la capa App para no romper
    el experimento de Zonal Shift de la Fase 1 (el tráfico debe permanecer
    confinado por zona antes de que ARC lo redirija).
  EOT
  default     = true
}

variable "enable_zonal_shift" {
  type        = bool
  description = "Habilita ARC Zonal Shift en el ALB. Solo tiene sentido en ALBs públicos (internet-facing)."
  default     = true
}

# ------- Target Group -------
variable "tg_port" {
  type        = number
  description = "Puerto en el que los targets (instancias EC2) reciben tráfico."
  default     = 80
}

variable "tg_protocol" {
  type        = string
  description = "Protocolo para enviar tráfico a los targets (HTTP o HTTPS)."
  default     = "HTTP"
}

variable "tg_target_type" {
  type        = string
  description = "Tipo de target: 'instance' para EC2 standalone, 'ip' para Fargate."
  default     = "instance"
}

variable "deregistration_delay" {
  type        = number
  description = "Segundos que el ALB espera antes de deregistrar un target en drenado."
  default     = 30
}

# ------- Health Check -------
variable "hc_path" {
  type        = string
  description = "Ruta HTTP que el ALB usa para los health checks."
  default     = "/health.html"
}

variable "hc_interval" {
  type        = number
  description = "Segundos entre peticiones de health check consecutivas."
  default     = 15
}

variable "hc_timeout" {
  type        = number
  description = "Segundos tras los cuales un health check se considera fallido."
  default     = 5
}

variable "hc_healthy_threshold" {
  type        = number
  description = "Éxitos consecutivos necesarios para marcar un target como healthy."
  default     = 2
}

variable "hc_unhealthy_threshold" {
  type        = number
  description = "Fallos consecutivos necesarios para marcar un target como unhealthy."
  default     = 3
}

variable "hc_matcher" {
  type        = string
  description = "Códigos HTTP que indican una respuesta healthy."
  default     = "200-299"
}
