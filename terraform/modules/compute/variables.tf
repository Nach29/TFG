# =============================================================================
# Compute module variables
# =============================================================================

variable "name_prefix" {
  description = "Prefix used to name the Launch Template and ASG (e.g. 'tfg-web-frankfurt')."
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the Launch Template (Amazon Linux 2023 recommended)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type used by the Launch Template."
  type        = string
  default     = "t3.micro"
}

variable "subnet_ids" {
  description = "List of private subnet IDs where the ASG deploys instances (multi-AZ)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of Security Group IDs attached to each launched instance."
  type        = list(string)
}

variable "iam_instance_profile_name" {
  description = "IAM Instance Profile name to attach (SSM plus tier-specific permissions)."
  type        = string
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Root EBS volume type. gp3 is cheaper and faster than gp2."
  type        = string
  default     = "gp3"
}

variable "user_data" {
  description = "Already-rendered user data script string. It is base64-encoded internally. Null disables user data."
  type        = string
  default     = null
}

variable "desired_capacity" {
  description = "Desired number of instances in the ASG. Frankfurt: 3, Ireland: 1."
  type        = number
  default     = 1
}

variable "min_size" {
  description = "Minimum number of instances the ASG must keep active."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances the ASG can scale to."
  type        = number
  default     = 6
}

variable "target_group_arns" {
  description = "List of ALB Target Group ARNs where the ASG automatically registers instances."
  type        = list(string)
  default     = []
}

variable "additional_tags" {
  description = "Additional tags to merge into the Launch Template and propagate to instances."
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "Common tags that must be explicitly propagated to ASG instances and volumes."
  type        = map(string)
  default     = {}
}
