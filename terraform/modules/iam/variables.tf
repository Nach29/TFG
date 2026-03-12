# =============================================================================
# IAM MODULE — variables.tf
# =============================================================================

variable "role_name" {
  description = "Name of the IAM Role"
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the IAM Instance Profile"
  type        = string
}

variable "assume_role_service" {
  description = "AWS service principal that is allowed to assume this role (e.g. 'ec2.amazonaws.com')"
  type        = string
  default     = "ec2.amazonaws.com"
}

variable "managed_policy_arns" {
  description = "List of AWS Managed Policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = <<-EOT
    Map of inline policies to embed directly in the role.
    Key   = policy name (must be unique within the role)
    Value = JSON policy document string (use jsonencode() in the caller)
  EOT
  type        = map(string)
  default     = {}
}
