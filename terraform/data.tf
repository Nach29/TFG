# =============================================================================
# DATA SOURCES
# Best practice: use AWS SSM Parameter Store to fetch the latest AL2023 AMI
# so the code never needs a hardcoded AMI ID that becomes stale.
# Ref: https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-public-parameters-ami.html
# =============================================================================

data "aws_ssm_parameter" "amazon_linux_2023" {
  # Public parameter maintained by AWS — always points to the latest AL2023 AMI
  # for x86_64 in the configured region.
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
