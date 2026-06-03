# =============================================================================
# Compute module
#
# Replaces aws_instance with:
#   aws_launch_template  -> defines instance configuration
#   aws_autoscaling_group -> manages lifecycle and capacity
#
# Change benefits:
#   - desired_capacity is configurable per region (3 active, 1 standby)
#   - Auto-registration in Target Groups through var.target_group_arns
#   - Automatic elasticity after instance failures
#   - Compatible with ARC Region Switch (the plan can modify desired_capacity)
#
# Security (keeps all Phase 1 hardening):
#   - IMDSv2 required (http_tokens = "required")
#   - Encrypted root EBS volume
#   - No SSH (access only through SSM Session Manager)
# =============================================================================

# Launch Template
# Defines the template used by the ASG to launch each instance.
# Equivalent to the previous aws_instance, but decoupled from capacity management.
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  description   = "Launch template for ${var.name_prefix} ASG"

  # User data: the caller passes the already-rendered string with templatefile().
  user_data = var.user_data != null ? base64encode(var.user_data) : null

  # IAM profile: SSM plus tier-specific permissions (web/app).
  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  # Security Groups
  vpc_security_group_ids = var.security_group_ids

  # Enforce IMDSv2: prevents SSRF credential theft attacks.
  # Ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Root EBS: encryption at rest, with no extra cost on gp3.
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = var.root_volume_type
      volume_size           = var.root_volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Tag propagation: launched instances inherit these tags.
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.common_tags,
      { Name = var.name_prefix },
      var.additional_tags
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      var.common_tags,
      { Name = "${var.name_prefix}-vol" },
      var.additional_tags
    )
  }

  tags = merge(
    var.common_tags,
    { Name = "${var.name_prefix}-lt" },
    var.additional_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
# Manages instance capacity and lifecycle.
# Automatically registers in the configured target group(s).
resource "aws_autoscaling_group" "this" {
  name_prefix = "${var.name_prefix}-asg-"

  # Multi-AZ distribution: one private subnet per AZ.
  vpc_zone_identifier = var.subnet_ids

  desired_capacity = var.desired_capacity
  min_size         = var.min_size
  max_size         = var.max_size

  # Automatic registration in the provided ALB Target Groups.
  target_group_arns = var.target_group_arns

  # ELB health checks are more precise than EC2 checks and replace instances
  # that fail the ALB health check, not only EC2-level checks.
  health_check_type         = "ELB"
  health_check_grace_period = 120 # seconds; gives user_data time to start

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # Instance refresh strategy: gradually replaces instances when the Launch
  # Template changes (e.g., new AMI or user_data).
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = var.name_prefix
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  dynamic "tag" {
    for_each = var.additional_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    # Ignore desired_capacity changes made by ARC Region Switch Plan or by
    # automatic scaling policies during normal operation.
    ignore_changes = [desired_capacity]
  }
}

# =============================================================================
# Required providers: allows the root module to pass provider aliases.
# Ref: https://developer.hashicorp.com/terraform/language/modules/develop/providers
# =============================================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.31, < 7.0"
    }
  }
}
