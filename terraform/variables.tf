# =============================================================================
# Root variables
#
# Defaults are intentionally small to keep the TFG environment affordable while
# still demonstrating zonal and regional resilience patterns.
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "Primary AWS region. Frankfurt is the active region."
  type        = string
  default     = "eu-central-1"
}

variable "dr_region" {
  description = "Disaster Recovery AWS region. Ireland is the warm standby region."
  type        = string
  default     = "eu-west-1"
}

variable "project_prefix" {
  description = "Name prefix applied to project resources."
  type        = string
  default     = "tfg-student-icolasma-TFG"
}

variable "domain_name" {
  description = "Root domain name. The public Route 53 hosted zone must already exist."
  type        = string
  default     = "dontpushthis.link"
}

# -----------------------------------------------------------------------------
# Network - Frankfurt active region
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the active VPC in Frankfurt."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Three Availability Zones used by the active region deployment."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for Frankfurt, one per Availability Zone."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs for Frankfurt, one per Availability Zone."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

# -----------------------------------------------------------------------------
# Network - Ireland warm standby region
# -----------------------------------------------------------------------------

variable "dr_vpc_cidr" {
  description = "CIDR block for the DR VPC in Ireland. It must not overlap Frankfurt."
  type        = string
  default     = "10.1.0.0/16"
}

variable "dr_availability_zones" {
  description = "Three Availability Zones used by the warm standby region."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "dr_public_subnet_cidrs" {
  description = "Public subnet CIDRs for Ireland, one per Availability Zone."
  type        = list(string)
  default     = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
}

variable "dr_private_subnet_cidrs" {
  description = "Private subnet CIDRs for Ireland, one per Availability Zone."
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
}

# -----------------------------------------------------------------------------
# EC2 and Auto Scaling
# -----------------------------------------------------------------------------

variable "ami_id" {
  description = <<-EOT
    Optional AMI ID for EC2 instances.
    When null, Terraform resolves the latest Amazon Linux 2023 AMI from AWS SSM
    Parameter Store in each region.
  EOT
  type        = string
  default     = null
}

variable "web_instance_type" {
  description = "EC2 instance type for the Web tier."
  type        = string
  default     = "t3.micro"
}

variable "app_instance_type" {
  description = "EC2 instance type for the App tier."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Root EBS volume type."
  type        = string
  default     = "gp3"
}

# -----------------------------------------------------------------------------
# Auto Scaling capacity - Frankfurt active region
# -----------------------------------------------------------------------------

variable "web_asg_desired" {
  description = "Desired capacity for the Web ASG in Frankfurt."
  type        = number
  default     = 3
}

variable "web_asg_min" {
  description = "Minimum capacity for the Web ASG in Frankfurt."
  type        = number
  default     = 1
}

variable "web_asg_max" {
  description = "Maximum capacity for the Web ASG in Frankfurt."
  type        = number
  default     = 6
}

variable "app_asg_desired" {
  description = "Desired capacity for the App ASG in Frankfurt."
  type        = number
  default     = 3
}

variable "app_asg_min" {
  description = "Minimum capacity for the App ASG in Frankfurt."
  type        = number
  default     = 1
}

variable "app_asg_max" {
  description = "Maximum capacity for the App ASG in Frankfurt."
  type        = number
  default     = 6
}

# -----------------------------------------------------------------------------
# Auto Scaling capacity - Ireland warm standby region
# -----------------------------------------------------------------------------

variable "dr_web_asg_desired" {
  description = "Desired capacity for the Web ASG in Ireland."
  type        = number
  default     = 1
}

variable "dr_web_asg_min" {
  description = "Minimum capacity for the Web ASG in Ireland."
  type        = number
  default     = 1
}

variable "dr_web_asg_max" {
  description = "Maximum capacity for the Web ASG in Ireland."
  type        = number
  default     = 6
}

variable "dr_app_asg_desired" {
  description = "Desired capacity for the App ASG in Ireland."
  type        = number
  default     = 1
}

variable "dr_app_asg_min" {
  description = "Minimum capacity for the App ASG in Ireland."
  type        = number
  default     = 1
}

variable "dr_app_asg_max" {
  description = "Maximum capacity for the App ASG in Ireland."
  type        = number
  default     = 6
}

# -----------------------------------------------------------------------------
# Ports
# -----------------------------------------------------------------------------

variable "web_port" {
  description = "TCP port served by the Web tier."
  type        = number
  default     = 80
}

variable "app_port" {
  description = "TCP port served by the App tier."
  type        = number
  default     = 8080
}

# -----------------------------------------------------------------------------
# ALB and Route 53
# -----------------------------------------------------------------------------

variable "alb_listener_port" {
  description = "Port exposed by the ALB listener."
  type        = number
  default     = 80
}

variable "alb_health_check_path" {
  description = "HTTP path used by ALB target group health checks."
  type        = string
  default     = "/health.html"
}

variable "arc_route53_health_check_id_frankfurt" {
  description = "ARC Region Switch health check ID for the Frankfurt DNS record."
  type        = string
  default     = "28bd64da-9556-4ab0-b351-16c25988048b"
}

variable "arc_route53_health_check_id_ireland" {
  description = "ARC Region Switch health check ID for the Ireland DNS record."
  type        = string
  default     = "aa6f3397-8796-44ce-ad5c-53802612d253"
}

variable "alb_idle_timeout" {
  description = "ALB idle connection timeout in seconds."
  type        = number
  default     = 60
}

# -----------------------------------------------------------------------------
# DynamoDB
# -----------------------------------------------------------------------------

variable "dynamodb_table_name" {
  description = "DynamoDB sessions table name."
  type        = string
  default     = "tfg-student-icolasma-TFG-sessions"
}

variable "dynamodb_hash_key" {
  description = "DynamoDB partition key attribute name."
  type        = string
  default     = "sessionId"
}

variable "dynamodb_pitr_enabled" {
  description = "Enable DynamoDB point-in-time recovery."
  type        = bool
  default     = false
}
