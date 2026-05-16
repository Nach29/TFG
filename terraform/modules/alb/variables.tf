# =============================================================================
# ALB module variables
# =============================================================================

# ------- General -------
variable "name" {
  type        = string
  description = "Name for the ALB and derived resources (TG, listener)."
}

variable "tags_lb" {
  type        = map(string)
  description = "Tags to apply to the ALB resource."
  default     = {}
}

variable "tags_tg" {
  type        = map(string)
  description = "Tags to apply to the Target Group."
  default     = {}
}

# ------- Network -------
variable "vpc_id" {
  type        = string
  description = "VPC ID where the Target Group is created."
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the ALB (minimum 2 AZs)."
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of Security Group IDs to attach to the ALB."
}

# ------- ALB Settings -------
variable "internal" {
  type        = bool
  description = <<-EOT
    true  = internal ALB (not internet-accessible), used for the App tier.
    false = public ALB (internet-facing), used by end clients.
  EOT
  default     = false
}

variable "drop_invalid_header_fields" {
  type        = bool
  description = "Drop malformed HTTP headers. Recommended true to prevent HTTP desync attacks."
  default     = true
}

variable "enable_cross_zone_load_balancing" {
  type        = bool
  description = <<-EOT
    Habilita el balanceo de carga entre zonas.
    CRITICAL: Must be FALSE on the App tier Internal ALB to avoid breaking
    the Phase 1 Zonal Shift experiment (traffic must remain zone-confined
    before ARC redirects it).
  EOT
  default     = true
}

variable "enable_zonal_shift" {
  type        = bool
  description = "Enable ARC Zonal Shift on the ALB. Only meaningful on public ALBs (internet-facing)."
  default     = true
}

# ------- Target Group -------
variable "tg_port" {
  type        = number
  description = "Port where targets (EC2 instances) receive traffic."
  default     = 80
}

variable "tg_protocol" {
  type        = string
  description = "Protocol used to send traffic to targets (HTTP or HTTPS)."
  default     = "HTTP"
}

variable "tg_target_type" {
  type        = string
  description = "Target type: 'instance' for standalone EC2, 'ip' for Fargate."
  default     = "instance"
}

variable "deregistration_delay" {
  type        = number
  description = "Seconds the ALB waits before deregistering a draining target."
  default     = 30
}

# ------- Health Check -------
variable "hc_path" {
  type        = string
  description = "HTTP path used by the ALB for health checks."
  default     = "/health.html"
}

variable "hc_interval" {
  type        = number
  description = "Seconds between consecutive health check requests."
  default     = 15
}

variable "hc_timeout" {
  type        = number
  description = "Seconds after which a health check is considered failed."
  default     = 5
}

variable "hc_healthy_threshold" {
  type        = number
  description = "Consecutive successes required to mark a target as healthy."
  default     = 2
}

variable "hc_unhealthy_threshold" {
  type        = number
  description = "Consecutive failures required to mark a target as unhealthy."
  default     = 3
}

variable "hc_matcher" {
  type        = string
  description = "HTTP codes that indicate a healthy response."
  default     = "200-299"
}
