# =============================================================================
# COMPUTE MODULE — main.tf
#
# Deploys a single, standalone EC2 instance (Amazon Linux 2023).
# Security hardening:
#   - Port 22 (SSH) is NOT opened — access via SSM Session Manager only.
#   - IMDSv2 is enforced (http_tokens = "required")
#   - Root EBS volume is encrypted
# =============================================================================

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile_name

  # user_data accepts a raw string. Terraform sends it to EC2 as-is.
  # templatefile() in the caller renders the template before passing it here.
  user_data = var.user_data

  # Enforce IMDSv2 — prevents SSRF-based credential theft attacks.
  # Ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    encrypted             = true # Encrypt at rest — no extra cost
    delete_on_termination = true

    tags = {
      Name = "${var.instance_name}-root-vol"
    }
  }

  tags = merge(
    {
      Name = var.instance_name
    },
    var.additional_tags
  )

  lifecycle {
    # Replacing the AMI (e.g. OS patch) should create the new instance first
    # before destroying the old one to maintain availability.
    create_before_destroy = true

    # Prevents Terraform from rebuilding the instance if only user_data changes
    # after initial provisioning.
    ignore_changes = [user_data]
  }
}
