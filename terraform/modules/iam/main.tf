# =============================================================================
# IAM MODULE — main.tf
#
# Creates a generic IAM Role + optional managed/inline policy attachments
# + an Instance Profile for EC2 use.
# Follows the principle of least privilege — callers specify only what's needed.
# =============================================================================

# Trust policy document — allows the specified AWS service to assume this role
data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "AllowServiceAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = [var.assume_role_service]
    }
  }
}

# ---------------------------------------------------------------------------
# IAM Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  # Propagate default_tags to the role
  tags = {
    Name = var.role_name
  }
}

# ---------------------------------------------------------------------------
# Managed Policy Attachments (e.g. AmazonSSMManagedInstanceCore)
# Uses for_each on a set so Terraform tracks each attachment independently.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# Inline Policies (e.g. granular DynamoDB access for App tier)
# Inline policies are destroyed with the role, ensuring no orphaned policies.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

# ---------------------------------------------------------------------------
# Instance Profile — required to attach the role to an EC2 instance
# ---------------------------------------------------------------------------
resource "aws_iam_instance_profile" "this" {
  name = var.instance_profile_name
  role = aws_iam_role.this.name

  tags = {
    Name = var.instance_profile_name
  }
}
