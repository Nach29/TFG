# =============================================================================
# COMPUTE MODULE — variables.tf
# =============================================================================

variable "instance_name" {
  description = "Value for the Name tag of the EC2 instance"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance (Amazon Linux 2023 recommended)"
  type        = string
}

variable "instance_type" {
  description = <<-EOT
    EC2 instance type.
    Default: t3.micro (~$0.0104/hr, cheapest current-gen). 
    Alternatively: t2.micro (AWS Free Tier eligible, 750 hrs/month for 12 months).
  EOT
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "ID of the subnet in which to launch the instance"
  type        = string
}

variable "security_group_ids" {
  description = "List of Security Group IDs to associate with the instance"
  type        = list(string)
}

variable "iam_instance_profile_name" {
  description = "Name of the IAM Instance Profile to attach (for SSM access and other permissions)"
  type        = string
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GiB"
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Type of the root EBS volume. gp3 is cheaper and faster than gp2."
  type        = string
  default     = "gp3"
}

variable "user_data" {
  description = "Raw user data script string. Use templatefile() in the caller. Null disables user data."
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Additional tags to merge into the instance's tags block"
  type        = map(string)
  default     = {}
}
