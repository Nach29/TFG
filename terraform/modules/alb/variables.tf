# =============================================================================
# ALB MODULE — variables.tf
# =============================================================================

# ------- General -------
variable "name" {
  type        = string
  description = "Name for the ALB and derived resources (target group, listener)."
}

variable "tags_lb" {
  type        = map(string)
  description = "Tags to apply to the Application Load Balancer resource."
  default     = {}
}

variable "tags_tg" {
  type        = map(string)
  description = "Tags to apply to the Target Group resource."
  default     = {}
}

# ------- Network -------
variable "vpc_id" {
  type        = string
  description = "ID of the VPC where the Target Group will be created."
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs for the ALB (must span at least 2 AZs)."
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of Security Group IDs to attach to the ALB."
}

# ------- ALB Settings -------
variable "drop_invalid_header_fields" {
  type        = bool
  description = "Drop malformed HTTP header fields. Recommended true to prevent HTTP desync attacks."
  default     = true
}

# ------- Target Group -------
variable "tg_port" {
  type        = number
  description = "Port on which targets (EC2 instances) receive traffic."
  default     = 80
}

variable "tg_protocol" {
  type        = string
  description = "Protocol used to send traffic to targets (HTTP or HTTPS)."
  default     = "HTTP"
}

variable "tg_target_type" {
  type        = string
  description = "Target type: 'instance' for EC2, 'ip' for ECS Fargate."
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
  description = "HTTP path the ALB uses for health checks. Points to the static file for a shallow (gray failure) check."
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
  description = "Consecutive successes required to mark a target healthy."
  default     = 2
}

variable "hc_unhealthy_threshold" {
  type        = number
  description = "Consecutive failures required to mark a target unhealthy."
  default     = 3
}

variable "hc_matcher" {
  type        = string
  description = "HTTP status codes that indicate a healthy response."
  default     = "200-299"
}
