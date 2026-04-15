# =============================================================================
# Data sources
# =============================================================================

# Latest Amazon Linux 2023 AMI for Frankfurt.
data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Latest Amazon Linux 2023 AMI for Ireland.
data "aws_ssm_parameter" "amazon_linux_2023_ireland" {
  provider = aws.ireland
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Existing public hosted zone for the service domain.
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Current AWS account, used in IAM policies and ARNs.
data "aws_caller_identity" "current" {}
