# =============================================================================
# ROOT MAIN.TF — Wires all modules together
#
# Architecture:
#   Internet → ALB (public subnets) → Web EC2 x3 (private, 1/AZ)
#                                    → App EC2 x3 (private, 1/AZ)
#                                    → DynamoDB (App tier only, via IAM)
#
# Traffic flow:
#   Client → ALB:80 → Web instance:80 → App instance:8080 → DynamoDB
#
# Naming convention: tfg-student-icolasma-TFG-[resource]
# All resources inherit Project/Owner/ManagedBy tags via provider default_tags.
# =============================================================================

locals {
  # Resolve AMI: use var.ami_id if explicitly set, otherwise use latest AL2023
  # fetched from AWS SSM Parameter Store (best practice — never hardcode AMIs)
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.amazon_linux_2023.value
}

# =============================================================================
# 1. VPC — Network foundation
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
# 2. SECURITY GROUPS
# Order matters: SGs are created sequentially because Web SG references ALB SG,
# and App SG references Web SG.
# =============================================================================

# ── ALB Security Group ────────────────────────────────────────────────────────
# Accepts HTTP (80) and HTTPS (443) from the public internet.
module "sg_alb" {
  source = "./modules/security"

  name        = "${var.project_prefix}-alb-sg"
  description = "ALB SG: allows HTTP/HTTPS inbound from the internet"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.project_prefix}-alb-sg" }

  ingress_rules = [
    {
      description = "HTTP from internet"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTPS from internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  # Default egress (allow all outbound) is inherited from the module variable default
}

# ── Web Tier Security Group ───────────────────────────────────────────────────
# Accepts web traffic ONLY from the ALB SG. No SSH (port 22) — SSM only.
module "sg_web" {
  source = "./modules/security"

  name        = "${var.project_prefix}-web-sg"
  description = "Web SG: allows inbound from ALB SG on web port only"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.project_prefix}-web-sg" }

  ingress_rules = [
    {
      description     = "HTTP from ALB"
      from_port       = var.web_port
      to_port         = var.web_port
      protocol        = "tcp"
      security_groups = [module.sg_alb.security_group_id]
    }
  ]
}

# ── App Tier Security Group ───────────────────────────────────────────────────
# Accepts app traffic ONLY from the Web SG. No SSH. No internet exposure.
module "sg_app" {
  source = "./modules/security"

  name        = "${var.project_prefix}-app-sg"
  description = "App SG: allows inbound from Web SG on app port only"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${var.project_prefix}-app-sg" }

  ingress_rules = [
    {
      description     = "App traffic from Web tier"
      from_port       = var.app_port
      to_port         = var.app_port
      protocol        = "tcp"
      security_groups = [module.sg_web.security_group_id]
    }
  ]
}

# =============================================================================
# 3. DYNAMODB TABLE — Created before IAM so we can inject its ARN into the
#    App tier's inline policy
# =============================================================================
module "dynamodb" {
  source = "./modules/dynamodb"

  table_name = var.dynamodb_table_name
  hash_key   = var.dynamodb_hash_key

  attributes = [
    {
      name = var.dynamodb_hash_key
      type = "S" # String partition key (sessionId)
    }
  ]

  point_in_time_recovery_enabled = var.dynamodb_pitr_enabled
  server_side_encryption_enabled = true
}

# =============================================================================
# 4. IAM ROLES + INSTANCE PROFILES
# Principle of Least Privilege:
#   - Web instances: SSM access only (no DynamoDB)
#   - App instances: SSM + scoped DynamoDB Read/Write on specific table ARN
# =============================================================================

# ── Web IAM Role (SSM only) ───────────────────────────────────────────────────
module "iam_web" {
  source = "./modules/iam"

  role_name             = "${var.project_prefix}-web-role"
  instance_profile_name = "${var.project_prefix}-web-instance-profile"
  assume_role_service   = "ec2.amazonaws.com"

  managed_policy_arns = [
    # Provides Systems Manager Session Manager, Run Command, and Patch Manager
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  # No inline policies — Web instances have NO DynamoDB access
}

# ── App IAM Role (SSM + DynamoDB least-privilege) ────────────────────────────
module "iam_app" {
  source = "./modules/iam"

  role_name             = "${var.project_prefix}-app-role"
  instance_profile_name = "${var.project_prefix}-app-instance-profile"
  assume_role_service   = "ec2.amazonaws.com"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]

  # Inline policy — grants Read/Write ONLY to the specific DynamoDB table ARN.
  # Actions are the minimum required for a session-based application.
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
            "dynamodb:Scan"
          ]
          # Scoped to the exact table ARN — not "*" — enforcing least privilege
          Resource = module.dynamodb.table_arn
        }
      ]
    })
  }
}

# =============================================================================
# 5. EC2 INSTANCES — Web Tier (3 instances, one per AZ, private subnets)
# count = 3, aligned with var.availability_zones by index
# =============================================================================
module "web_instances" {
  source = "./modules/compute"
  count  = length(var.availability_zones)

  instance_name             = "${var.project_prefix}-web-${count.index + 1}"
  ami_id                    = local.ami_id
  instance_type             = var.web_instance_type
  subnet_id                 = module.vpc.private_subnet_ids[count.index]
  security_group_ids        = [module.sg_web.security_group_id]
  iam_instance_profile_name = module.iam_web.instance_profile_name
  root_volume_size          = var.root_volume_size
  root_volume_type          = var.root_volume_type

  # Render user data template — sets up Apache httpd + PHP on the Web tier.
  # app_private_ip: private IP of the AZ-aligned App instance, used by the
  # PHP page to call the App tier. This creates an implicit Terraform dependency:
  # app instances are created first so their IPs are known at plan time.
  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    instance_name     = "${var.project_prefix}-web-${count.index + 1}"
    tier              = "web"
    availability_zone = var.availability_zones[count.index]
    app_port          = var.app_port
    app_private_ip    = module.app_instances[count.index].private_ip
  })

  additional_tags = {
    Tier = "Web"
    AZ   = var.availability_zones[count.index]
  }
}

# =============================================================================
# 6. EC2 INSTANCES — App Tier (3 instances, one per AZ, private subnets)
# =============================================================================
module "app_instances" {
  source = "./modules/compute"
  count  = length(var.availability_zones)

  instance_name             = "${var.project_prefix}-app-${count.index + 1}"
  ami_id                    = local.ami_id
  instance_type             = var.app_instance_type
  subnet_id                 = module.vpc.private_subnet_ids[count.index]
  security_group_ids        = [module.sg_app.security_group_id]
  iam_instance_profile_name = module.iam_app.instance_profile_name
  root_volume_size          = var.root_volume_size
  root_volume_type          = var.root_volume_type

  # Render user data template — sets up Python HTTP server on App tier.
  # app_private_ip is unused in the 'app' branch but must be present because
  # templatefile() validates ALL variable references in the file at parse time,
  # regardless of which %{ if } branch is active.
  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    instance_name     = "${var.project_prefix}-app-${count.index + 1}"
    tier              = "app"
    availability_zone = var.availability_zones[count.index]
    app_port          = var.app_port
    app_private_ip    = "" # unused in app tier branch — required by templatefile() parser
  })

  additional_tags = {
    Tier = "App"
    AZ   = var.availability_zones[count.index]
  }
}

# =============================================================================
# 7. APPLICATION LOAD BALANCER
#    - Internet-facing (internal = false), public subnets across 3 AZs
#    - HTTP:80 → forward to Web tier target group (no HTTPS for PoC)
#    - enable_zonal_shift = true (ARC Zonal Shift ready)
#    - Accessed via its AWS-generated DNS name
# =============================================================================
module "alb" {
  source = "./modules/alb"

  name               = "${var.project_prefix}-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.sg_alb.security_group_id]

  tags_lb = { Name = "${var.project_prefix}-alb" }
  tags_tg = { Name = "${var.project_prefix}-alb-tg" }

  # Target Group — EC2 instances require target_type = "instance"
  tg_port        = var.web_port
  tg_protocol    = "HTTP"
  tg_target_type = "instance"

  # Health check
  hc_path = var.alb_health_check_path
}


# Register the 3 Web instances in the ALB target group.
# Kept outside the module so the module stays generic (no hardcoded count/compute).
resource "aws_lb_target_group_attachment" "web" {
  count = length(var.availability_zones)

  target_group_arn = module.alb.target_group_arn
  target_id        = module.web_instances[count.index].instance_id
  port             = var.web_port
}

module "auto_recovery" {
  source = "./modules/auto_recovery"
  project_prefix     = var.project_prefix
  alb_arn            = module.alb.alb_arn
  alb_arn_suffix     = module.alb.alb_arn_suffix
  availability_zones = var.availability_zones
}