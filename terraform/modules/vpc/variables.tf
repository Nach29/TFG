# =============================================================================
# VPC module variables
# =============================================================================

variable "project_name" {
  description = "Name prefix applied to all resources created by this module"
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of Availability Zone names. Module expects exactly 3."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets. Must be index-aligned with availability_zones."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets. Must be index-aligned with availability_zones."
  type        = list(string)
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC (required for SSM connectivity)"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS resolution in the VPC (required for SSM connectivity)"
  type        = bool
  default     = true
}
