# =============================================================================
# Root module
#
# This module deploys the full TFG platform:
#   - Frankfurt as the active region
#   - Ireland as the warm standby region
#   - Route 53 failover routing between both public ALBs
#   - ARC Zonal Shift automation for zonal incidents
#   - ARC Region Switch orchestration for regional failover
#
# Request path:
#   Internet -> Public ALB -> Web ASG -> Internal ALB -> App ASG -> DynamoDB
#
# Non-negotiable design constraints:
#   - Internal ALB cross-zone load balancing stays disabled
#   - EC2 access is only through SSM Session Manager
#   - Cost optimization uses t3.micro and one NAT Gateway per region
# =============================================================================

locals {
  # Frankfurt AMI: use a pinned AMI only when var.ami_id is provided.
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.amazon_linux_2023.value

  # Ireland AMIs are regional, so the DR region resolves its own AL2023 AMI.
  ami_id_ireland = data.aws_ssm_parameter.amazon_linux_2023_ireland.value

  # AWS ALB names are short, so keep a compact prefix available for those resources.
  short_prefix = "tfg-icolasma"

  # ASG-launched EC2 instances and EBS volumes need explicit tag propagation.
  common_tags = {
    Project   = "TFG"
    TFG       = "true"
    Owner     = "student-icolasma"
    ManagedBy = "Terraform"
    Phase     = "2-DR"
  }

  ireland_common_tags = merge(local.common_tags, {
    Role = "WarmStandby"
  })
}

# =============================================================================
# Frankfurt active region
# =============================================================================

# =============================================================================
# 1. VPC Frankfurt
# =============================================================================
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# =============================================================================
# 2. SECURITY GROUPS - Frankfurt
# Dependency order:
#   sg_alb -> sg_web (references sg_alb)
#   sg_internal_alb (in front of the App tier)
#   sg_app -> references sg_internal_alb, not sg_web directly
# =============================================================================

# Public ALB
module "sg_alb" {
  source = "./modules/security"

  name        = "${local.short_prefix}-alb-sg"
  description = "ALB SG: allows HTTP from the internet"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.short_prefix}-alb-sg" }

  ingress_rules = [
    {
      description = "HTTP from the internet"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

# Web Tier
module "sg_web" {
  source = "./modules/security"

  name        = "${local.short_prefix}-web-sg"
  description = "Web SG: only accepts traffic from the public ALB"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.short_prefix}-web-sg" }

  ingress_rules = [
    {
      description     = "HTTP from public ALB"
      from_port       = var.web_port
      to_port         = var.web_port
      protocol        = "tcp"
      security_groups = [module.sg_alb.security_group_id]
    }
  ]
}

# Internal ALB (in front of the App tier)
module "sg_internal_alb" {
  source = "./modules/security"

  name        = "${local.short_prefix}-int-alb-sg"
  description = "Internal ALB SG: accepts Web tier traffic on the app port"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.short_prefix}-int-alb-sg" }

  ingress_rules = [
    {
      description     = "App port from Web tier"
      from_port       = var.app_port
      to_port         = var.app_port
      protocol        = "tcp"
      security_groups = [module.sg_web.security_group_id]
    }
  ]
}

# App Tier
module "sg_app" {
  source = "./modules/security"

  name        = "${local.short_prefix}-app-sg"
  description = "App SG: only accepts traffic from the Internal ALB"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.short_prefix}-app-sg" }

  ingress_rules = [
    {
      description     = "App traffic from Internal ALB"
      from_port       = var.app_port
      to_port         = var.app_port
      protocol        = "tcp"
      security_groups = [module.sg_internal_alb.security_group_id]
    }
  ]
}

# =============================================================================
# 3. DynamoDB Global Table v2 (active-active with eu-west-1)
# The table is created in eu-central-1 (default provider) with streams enabled.
# The replica block replicates all data to eu-west-1 in real time.
# IMPORTANT: because this is a Global Table, provider = aws.ireland is not used here.
# DynamoDB manages replication internally.
# =============================================================================
module "dynamodb" {
  source = "./modules/dynamodb"

  table_name = var.dynamodb_table_name
  hash_key   = var.dynamodb_hash_key

  attributes = [
    {
      name = var.dynamodb_hash_key
      type = "S"
    }
  ]

  replica_regions                = [var.dr_region] # eu-west-1
  point_in_time_recovery_enabled = var.dynamodb_pitr_enabled
  server_side_encryption_enabled = true
}

# =============================================================================
# 4. IAM ROLES Frankfurt
# =============================================================================

# Web Role (SSM only)
module "iam_web" {
  source = "./modules/iam"

  role_name             = "${var.project_prefix}-web-role"
  instance_profile_name = "${var.project_prefix}-web-instance-profile"
  assume_role_service   = "ec2.amazonaws.com"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

# App Role (SSM + DynamoDB least-privilege)
module "iam_app" {
  source = "./modules/iam"

  role_name             = "${var.project_prefix}-app-role"
  instance_profile_name = "${var.project_prefix}-app-instance-profile"
  assume_role_service   = "ec2.amazonaws.com"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]

  # Read/write access only to the specific table, following least privilege.
  # With Global Tables, the same policy is valid for local reads/writes;
  # cross-region replication is managed transparently by DynamoDB.
  inline_policies = {
    "dynamodb-sessions-readwrite" = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "DynamoDBSessionAccess"
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem",
            "dynamodb:Query",
            "dynamodb:Scan",
          ]
          Resource = module.dynamodb.table_arn
        }
      ]
    })
  }
}

# =============================================================================
# 5. INTERNAL ALB Frankfurt (in front of the App tier)
#
# CRITICAL: enable_cross_zone_load_balancing = false
#   If true, the Internal ALB would distribute requests across all App instances
#   in all AZs. That would break the Phase 1 Zonal Shift experiment:
#   shifting eu-central-1a should limit traffic to 1b and 1c, but with
#   cross_zone=true traffic could still reach 1a instances through the ALB.
#
# enable_zonal_shift = false: internal ALBs do not participate in ARC Zonal Shift
#   (the external public ALB performs the shift).
# =============================================================================
module "internal_alb" {
  source = "./modules/alb"

  name               = "${local.short_prefix}-int-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.sg_internal_alb.security_group_id]

  internal                         = true
  enable_cross_zone_load_balancing = false # Critical for the Zonal Shift experiment
  enable_zonal_shift               = false # Not applicable to internal ALBs

  tg_port        = var.app_port
  tg_protocol    = "HTTP"
  tg_target_type = "instance"
  hc_path        = "/index.html" # App tier serves JSON at the root path

  tags_lb = { Name = "${local.short_prefix}-int-alb" }
  tags_tg = { Name = "${local.short_prefix}-int-alb-tg" }
}

# =============================================================================
# 6. PUBLIC ALB Frankfurt (internet-facing, Zonal Shift enabled)
# =============================================================================
module "alb" {
  source = "./modules/alb"

  name               = "${local.short_prefix}-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.sg_alb.security_group_id]

  internal                         = false
  enable_cross_zone_load_balancing = true
  enable_zonal_shift               = true # Phase 1: ARC Zonal Shift enabled

  tg_port        = var.web_port
  tg_protocol    = "HTTP"
  tg_target_type = "instance"
  hc_path        = var.alb_health_check_path

  tags_lb = { Name = "${local.short_prefix}-alb" }
  tags_tg = { Name = "${local.short_prefix}-alb-tg" }
}

# =============================================================================
# 7. APP ASG Frankfurt (desired=3, registered in the Internal ALB)
# Created before the Web ASG so the Internal ALB DNS name is available
# when rendering the Web tier user_data.
# =============================================================================
module "app_asg" {
  source = "./modules/compute"

  name_prefix               = "${var.project_prefix}-app"
  ami_id                    = local.ami_id
  instance_type             = var.app_instance_type
  subnet_ids                = module.vpc.private_subnet_ids
  security_group_ids        = [module.sg_app.security_group_id]
  iam_instance_profile_name = module.iam_app.instance_profile_name

  desired_capacity  = var.app_asg_desired
  min_size          = var.app_asg_min
  max_size          = var.app_asg_max
  target_group_arns = [module.internal_alb.target_group_arn]

  root_volume_size = var.root_volume_size
  root_volume_type = var.root_volume_type
  common_tags      = local.common_tags

  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    tier                 = "app"
    app_port             = var.app_port
    app_internal_alb_dns = "" # Unused in the app branch of the template
  })

  additional_tags = { Tier = "App", Region = "Frankfurt" }
}

# =============================================================================
# 8. WEB ASG Frankfurt (desired=3, registered in the public ALB)
# user_data points to the Internal ALB DNS name, which remains stable when App IPs change.
# =============================================================================
module "web_asg" {
  source = "./modules/compute"

  name_prefix               = "${var.project_prefix}-web"
  ami_id                    = local.ami_id
  instance_type             = var.web_instance_type
  subnet_ids                = module.vpc.private_subnet_ids
  security_group_ids        = [module.sg_web.security_group_id]
  iam_instance_profile_name = module.iam_web.instance_profile_name

  desired_capacity  = var.web_asg_desired
  min_size          = var.web_asg_min
  max_size          = var.web_asg_max
  target_group_arns = [module.alb.target_group_arn]

  root_volume_size = var.root_volume_size
  root_volume_type = var.root_volume_type
  common_tags      = local.common_tags

  # Phase 2: pass the Internal ALB DNS name instead of a static IP.
  # The DNS name is immutable during the Internal ALB lifecycle.
  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    tier                 = "web"
    app_port             = var.app_port
    app_internal_alb_dns = module.internal_alb.alb_dns_name
  })

  additional_tags = { Tier = "Web", Region = "Frankfurt" }
}

# =============================================================================
# 9. AUTO RECOVERY (Phase 1 closed-loop Zonal Shift)
# =============================================================================
module "auto_recovery" {
  source = "./modules/auto_recovery"

  project_prefix     = var.project_prefix
  alb_arn            = module.alb.alb_arn
  alb_arn_suffix     = module.alb.alb_arn_suffix
  availability_zones = var.availability_zones
}

# =============================================================================
# IRELAND WARM STANDBY
# All resources use provider = aws.ireland.
# =============================================================================

# =============================================================================
# 10. VPC Ireland
# =============================================================================
module "vpc_ireland" {
  source    = "./modules/vpc"
  providers = { aws = aws.ireland }

  project_name         = "${var.project_prefix}-ireland"
  vpc_cidr             = var.dr_vpc_cidr
  availability_zones   = var.dr_availability_zones
  public_subnet_cidrs  = var.dr_public_subnet_cidrs
  private_subnet_cidrs = var.dr_private_subnet_cidrs
}

# =============================================================================
# 11. SECURITY GROUPS Ireland
# =============================================================================

module "sg_alb_ireland" {
  source    = "./modules/security"
  providers = { aws = aws.ireland }

  name        = "${local.short_prefix}-alb-sg-ie"
  description = "Ireland ALB SG: allows HTTP from the internet"
  vpc_id      = module.vpc_ireland.vpc_id
  tags        = { Name = "${local.short_prefix}-alb-sg-ie" }

  ingress_rules = [
    {
      description = "HTTP from the internet"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

module "sg_web_ireland" {
  source    = "./modules/security"
  providers = { aws = aws.ireland }

  name        = "${local.short_prefix}-web-sg-ie"
  description = "Ireland Web SG: only accepts traffic from the public ALB"
  vpc_id      = module.vpc_ireland.vpc_id
  tags        = { Name = "${local.short_prefix}-web-sg-ie" }

  ingress_rules = [
    {
      description     = "HTTP from Ireland public ALB"
      from_port       = var.web_port
      to_port         = var.web_port
      protocol        = "tcp"
      security_groups = [module.sg_alb_ireland.security_group_id]
    }
  ]
}

module "sg_internal_alb_ireland" {
  source    = "./modules/security"
  providers = { aws = aws.ireland }

  name        = "${local.short_prefix}-int-alb-sg-ie"
  description = "Ireland Internal ALB SG: accepts Web traffic on the app port"
  vpc_id      = module.vpc_ireland.vpc_id
  tags        = { Name = "${local.short_prefix}-int-alb-sg-ie" }

  ingress_rules = [
    {
      description     = "App port from Ireland Web tier"
      from_port       = var.app_port
      to_port         = var.app_port
      protocol        = "tcp"
      security_groups = [module.sg_web_ireland.security_group_id]
    }
  ]
}

module "sg_app_ireland" {
  source    = "./modules/security"
  providers = { aws = aws.ireland }

  name        = "${local.short_prefix}-app-sg-ie"
  description = "Ireland App SG: only accepts traffic from the Internal ALB"
  vpc_id      = module.vpc_ireland.vpc_id
  tags        = { Name = "${local.short_prefix}-app-sg-ie" }

  ingress_rules = [
    {
      description     = "App traffic from Ireland Internal ALB"
      from_port       = var.app_port
      to_port         = var.app_port
      protocol        = "tcp"
      security_groups = [module.sg_internal_alb_ireland.security_group_id]
    }
  ]
}

# =============================================================================
# 12. IAM ROLES Ireland
# IAM roles are global, but they are created here with the provider alias so the
# instance profile is created in the correct regional context.
# =============================================================================

module "iam_web_ireland" {
  source    = "./modules/iam"
  providers = { aws = aws.ireland }

  role_name             = "${var.project_prefix}-web-role-ie"
  instance_profile_name = "${var.project_prefix}-web-instance-profile-ie"
  assume_role_service   = "ec2.amazonaws.com"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

module "iam_app_ireland" {
  source    = "./modules/iam"
  providers = { aws = aws.ireland }

  role_name             = "${var.project_prefix}-app-role-ie"
  instance_profile_name = "${var.project_prefix}-app-instance-profile-ie"
  assume_role_service   = "ec2.amazonaws.com"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]

  # Read/write access to the local Global Table replica (same table, different replica).
  inline_policies = {
    "dynamodb-sessions-readwrite" = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "DynamoDBSessionAccess"
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
            "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan",
          ]
          # Ireland replica ARN (same table, different region).
          Resource = "arn:aws:dynamodb:${var.dr_region}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}"
        }
      ]
    })
  }
}

# =============================================================================
# 13. INTERNAL ALB Ireland (cross_zone=false, same as Frankfurt)
# =============================================================================
module "internal_alb_ireland" {
  source    = "./modules/alb"
  providers = { aws = aws.ireland }

  name               = "${local.short_prefix}-int-alb-ie"
  vpc_id             = module.vpc_ireland.vpc_id
  subnet_ids         = module.vpc_ireland.private_subnet_ids
  security_group_ids = [module.sg_internal_alb_ireland.security_group_id]

  internal                         = true
  enable_cross_zone_load_balancing = false # Same reasoning as Frankfurt
  enable_zonal_shift               = false

  tg_port        = var.app_port
  tg_protocol    = "HTTP"
  tg_target_type = "instance"
  hc_path        = "/index.html"

  tags_lb = { Name = "${local.short_prefix}-int-alb-ie" }
  tags_tg = { Name = "${local.short_prefix}-int-alb-tg-ie" }
}

# =============================================================================
# 14. PUBLIC ALB Ireland (Zonal Shift ON, failover endpoint)
# =============================================================================
module "alb_ireland" {
  source    = "./modules/alb"
  providers = { aws = aws.ireland }

  name               = "${local.short_prefix}-alb-ie"
  vpc_id             = module.vpc_ireland.vpc_id
  subnet_ids         = module.vpc_ireland.public_subnet_ids
  security_group_ids = [module.sg_alb_ireland.security_group_id]

  internal                         = false
  enable_cross_zone_load_balancing = true
  enable_zonal_shift               = true

  tg_port        = var.web_port
  tg_protocol    = "HTTP"
  tg_target_type = "instance"
  hc_path        = var.alb_health_check_path

  tags_lb = { Name = "${local.short_prefix}-alb-ie" }
  tags_tg = { Name = "${local.short_prefix}-alb-tg-ie" }
}

# =============================================================================
# 15. APP ASG Ireland (Warm Standby: desired=1)
# =============================================================================
module "app_asg_ireland" {
  source    = "./modules/compute"
  providers = { aws = aws.ireland }

  name_prefix               = "${var.project_prefix}-app-ie"
  ami_id                    = local.ami_id_ireland
  instance_type             = var.app_instance_type
  subnet_ids                = module.vpc_ireland.private_subnet_ids
  security_group_ids        = [module.sg_app_ireland.security_group_id]
  iam_instance_profile_name = module.iam_app_ireland.instance_profile_name

  desired_capacity  = var.dr_app_asg_desired # 1 (warm standby)
  min_size          = var.dr_app_asg_min
  max_size          = var.dr_app_asg_max
  target_group_arns = [module.internal_alb_ireland.target_group_arn]

  root_volume_size = var.root_volume_size
  root_volume_type = var.root_volume_type
  common_tags      = local.ireland_common_tags

  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    tier                 = "app"
    app_port             = var.app_port
    app_internal_alb_dns = ""
  })

  additional_tags = { Tier = "App", Region = "Ireland" }
}

# =============================================================================
# 16. WEB ASG Ireland (Warm Standby: desired=1)
# =============================================================================
module "web_asg_ireland" {
  source    = "./modules/compute"
  providers = { aws = aws.ireland }

  name_prefix               = "${var.project_prefix}-web-ie"
  ami_id                    = local.ami_id_ireland
  instance_type             = var.web_instance_type
  subnet_ids                = module.vpc_ireland.private_subnet_ids
  security_group_ids        = [module.sg_web_ireland.security_group_id]
  iam_instance_profile_name = module.iam_web_ireland.instance_profile_name

  desired_capacity  = var.dr_web_asg_desired # 1 (warm standby)
  min_size          = var.dr_web_asg_min
  max_size          = var.dr_web_asg_max
  target_group_arns = [module.alb_ireland.target_group_arn]

  root_volume_size = var.root_volume_size
  root_volume_type = var.root_volume_type
  common_tags      = local.ireland_common_tags

  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    tier                 = "web"
    app_port             = var.app_port
    app_internal_alb_dns = module.internal_alb_ireland.alb_dns_name
  })

  additional_tags = { Tier = "Web", Region = "Ireland" }
}

# =============================================================================
# ROUTE 53 FAILOVER DNS
# Route 53 is global: it does not require a provider alias and uses the default provider.
# =============================================================================

# =============================================================================
# 17. PRIMARY DNS RECORD - Frankfurt
# IMPORTANT:
#   - set_identifier contains the exact region so ARC Region Switch can
#     map this record set to eu-central-1.
#   - health_check_id uses the health check generated by ARC Region Switch.
# =============================================================================
resource "aws_route53_record" "primary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = var.aws_region
  health_check_id = var.arc_route53_health_check_id_frankfurt

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = false
  }
}

# =============================================================================
# 18. SECONDARY DNS RECORD - Ireland
# IMPORTANT:
#   - set_identifier contains the exact region so ARC Region Switch can
#     map this record set to eu-west-1.
#   - health_check_id uses the health check generated by ARC Region Switch.
# =============================================================================
resource "aws_route53_record" "secondary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier  = var.dr_region
  health_check_id = var.arc_route53_health_check_id_ireland

  alias {
    name                   = module.alb_ireland.alb_dns_name
    zone_id                = module.alb_ireland.alb_zone_id
    evaluate_target_health = false
  }
}

# =============================================================================
# ARC REGION SWITCH PLAN
# =============================================================================

# =============================================================================
# 20. IAM ROLE - Execution role for the ARC Region Switch Plan
# =============================================================================
data "aws_iam_policy_document" "arc_plan_assume_role" {
  statement {
    sid     = "AllowARCRegionSwitchAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["arc-region-switch.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "arc_execution_role" {
  name               = "${var.project_prefix}-arc-plan-execution-role"
  assume_role_policy = data.aws_iam_policy_document.arc_plan_assume_role.json

  tags = { Name = "${var.project_prefix}-arc-plan-execution-role" }
}

data "aws_iam_policy_document" "arc_plan_permissions" {
  statement {
    sid    = "AllowASGRead"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowASGMetricsRead"
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricStatistics"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowASGScaleUp"
    effect = "Allow"
    actions = [
      "autoscaling:UpdateAutoScalingGroup"
    ]
    resources = [
      module.app_asg.autoscaling_group_arn,
      module.app_asg_ireland.autoscaling_group_arn,
      module.web_asg.autoscaling_group_arn,
      module.web_asg_ireland.autoscaling_group_arn
    ]
  }

  statement {
    sid    = "AllowRoute53HealthCheckUpdate"
    effect = "Allow"
    actions = [
      "route53:UpdateHealthCheck",
      "route53:GetHealthCheck"
    ]
    resources = [
      "arn:aws:route53:::healthcheck/${var.arc_route53_health_check_id_frankfurt}",
      "arn:aws:route53:::healthcheck/${var.arc_route53_health_check_id_ireland}"
    ]
  }

  statement {
    sid    = "AllowRoute53ListRecords"
    effect = "Allow"
    actions = [
      "route53:ListResourceRecordSets"
    ]
    resources = [
      "arn:aws:route53:::hostedzone/${data.aws_route53_zone.main.zone_id}"
    ]
  }

  statement {
    sid    = "AllowARCValidation"
    effect = "Allow"
    actions = [
      "iam:SimulatePrincipalPolicy"
    ]
    resources = [
      aws_iam_role.arc_execution_role.arn
    ]
  }

  statement {
    sid    = "AllowARCReadPlan"
    effect = "Allow"
    actions = [
      "arc-region-switch:GetPlan",
      "arc-region-switch:GetPlanExecution",
      "arc-region-switch:ListPlanExecutions"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "arc_plan_permissions" {
  name   = "arc-region-switch-plan-policy"
  role   = aws_iam_role.arc_execution_role.id
  policy = data.aws_iam_policy_document.arc_plan_permissions.json
}

# =============================================================================
# 21. ARC REGION SWITCH PLAN - Core of TFG Phase 2
#
# Workflow:
#   Step 1: scale the Ireland App ASG.
#   Step 2: scale the Ireland Web ASG.
#   Step 3: redirect traffic through the Route 53 Health Check.
# =============================================================================
resource "aws_arcregionswitch_plan" "main_dr_plan" {
  name              = "${var.project_prefix}-dr-plan"
  execution_role    = aws_iam_role.arc_execution_role.arn
  recovery_approach = "activePassive"

  regions        = [var.aws_region, var.dr_region]
  primary_region = var.aws_region

  workflow {
    workflow_target_action = "activate"

    step {
      name                 = "scale-up-ireland-app-asg"
      execution_block_type = "EC2AutoScaling"

      ec2_asg_capacity_increase_config {
        asg {
          arn = module.app_asg.autoscaling_group_arn
        }

        asg {
          arn = module.app_asg_ireland.autoscaling_group_arn
        }

        target_percent               = 100
        capacity_monitoring_approach = "sampledMaxInLast24Hours"
        timeout_minutes              = 60
      }
    }

    step {
      name                 = "scale-up-ireland-web-asg"
      execution_block_type = "EC2AutoScaling"

      ec2_asg_capacity_increase_config {
        asg {
          arn = module.web_asg.autoscaling_group_arn
        }

        asg {
          arn = module.web_asg_ireland.autoscaling_group_arn
        }

        target_percent               = 100
        capacity_monitoring_approach = "sampledMaxInLast24Hours"
        timeout_minutes              = 60
      }
    }

    step {
      name                 = "failover-route53-traffic"
      execution_block_type = "Route53HealthCheck"

      route53_health_check_config {
        hosted_zone_id  = data.aws_route53_zone.main.zone_id
        record_name     = var.domain_name
        timeout_minutes = 60

        record_set {
          record_set_identifier = var.aws_region
          region                = var.aws_region
        }

        record_set {
          record_set_identifier = var.dr_region
          region                = var.dr_region
        }
      }
    }
  }

  tags = {
    Name = "${var.project_prefix}-dr-plan"
  }

  depends_on = [
    aws_iam_role_policy.arc_plan_permissions,
    aws_route53_record.primary,
    aws_route53_record.secondary,
    module.app_asg_ireland,
    module.web_asg_ireland
  ]
}
