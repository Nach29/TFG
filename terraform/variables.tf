# =============================================================================
# ROOT VARIABLES — All parameterized as per HashiCorp best practices.
# Defaults use the cheapest/free-tier options available.
# =============================================================================

# ── General ──────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "eu-central-1"
}

variable "project_prefix" {
  description = "Naming prefix applied to every resource. Convention: tfg-student-icolasma-TFG"
  type        = string
  default     = "tfg-student-icolasma-TFG"
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Exactly 3 AZs to deploy into. Must exist in var.aws_region."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per AZ (index-aligned)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — one per AZ (index-aligned)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

# ── EC2 Compute ───────────────────────────────────────────────────────────────

variable "ami_id" {
  description = <<-EOT
    AMI ID for EC2 instances (Amazon Linux 2023).
    When null (default), the latest AL2023 AMI is fetched automatically
    via the AWS SSM Parameter Store — the recommended approach.
    Override this only to pin a specific AMI version.
  EOT
  type        = string
  default     = null
}

variable "web_instance_type" {
  description = <<-EOT
    EC2 instance type for the Web tier.
    Default: t3.micro (~$0.0104/hr) — smallest current-gen burstable.
    Use t2.micro for AWS Free Tier (750 hrs/month, 12-month limit).
  EOT
  type        = string
  default     = "t3.micro"
}

variable "app_instance_type" {
  description = <<-EOT
    EC2 instance type for the App tier.
    Default: t3.micro (~$0.0104/hr) — smallest current-gen burstable.
    Use t2.micro for AWS Free Tier (750 hrs/month, 12-month limit).
  EOT
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB. Minimum recommended: 8 GiB."
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Root EBS volume type. gp3 is the current default, cheaper than gp2."
  type        = string
  default     = "gp3"
}

# ── Ports ─────────────────────────────────────────────────────────────────────

variable "web_port" {
  description = "TCP port on which Web tier instances serve HTTP traffic"
  type        = number
  default     = 80
}

variable "app_port" {
  description = "TCP port on which App tier instances serve HTTP traffic"
  type        = number
  default     = 8080
}

# ── ALB ──────────────────────────────────────────────────────────────────────

variable "alb_listener_port" {
  description = "Port on which the ALB listener accepts traffic"
  type        = number
  default     = 80
}

variable "alb_health_check_path" {
  description = "Health check path on Web instances. Points to the static file for the shallow (gray failure) chaos experiment."
  type        = string
  default     = "/health.html"
}

variable "alb_idle_timeout" {
  description = "Idle connection timeout in seconds for the ALB"
  type        = number
  default     = 60
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB application table"
  type        = string
  default     = "tfg-student-icolasma-TFG-sessions"
}

variable "dynamodb_hash_key" {
  description = "Attribute name to use as the partition (hash) key"
  type        = string
  default     = "sessionId"
}

variable "dynamodb_pitr_enabled" {
  description = "Enable Point-in-Time Recovery. Adds cost — disable for dev/demo."
  type        = bool
  default     = false
}

