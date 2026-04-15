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
}

# =============================================================================
# ████████████████████  FRÁNCFORT — REGIÓN ACTIVA  ████████████████████████████
# =============================================================================

# =============================================================================
# 1. VPC Fráncfort
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
# 2. SECURITY GROUPS — Fráncfort
# Orden de dependencias:
#   sg_alb → sg_web (referencia sg_alb)
#   sg_internal_alb (nuevo, delante de App tier)
#   sg_app → referencia sg_internal_alb (no sg_web directamente)
# =============================================================================

# ── ALB Público ───────────────────────────────────────────────────────────────
module "sg_alb" {
  source = "./modules/security"

  name        = "${local.short_prefix}-alb-sg"
  description = "ALB SG: permite HTTP/HTTPS desde internet"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.short_prefix}-alb-sg" }

  ingress_rules = [
    {
      description = "HTTP desde internet"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTPS desde internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

# ── Web Tier ──────────────────────────────────────────────────────────────────
module "sg_web" {
  source = "./modules/security"

  name        = "${local.short_prefix}-web-sg"
  description = "Web SG: solo acepta tráfico del ALB público"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.short_prefix}-web-sg" }

  ingress_rules = [
    {
      description     = "HTTP desde ALB público"
      from_port       = var.web_port
      to_port         = var.web_port
      protocol        = "tcp"
      security_groups = [module.sg_alb.security_group_id]
    }
  ]
}

# ── Internal ALB (delante de App tier) ────────────────────────────────────────
module "sg_internal_alb" {
  source = "./modules/security"

  name        = "${local.short_prefix}-int-alb-sg"
  description = "Internal ALB SG: acepta tráfico de la capa Web en el puerto app"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.short_prefix}-int-alb-sg" }

  ingress_rules = [
    {
      description     = "App port desde Web tier"
      from_port       = var.app_port
      to_port         = var.app_port
      protocol        = "tcp"
      security_groups = [module.sg_web.security_group_id]
    }
  ]
}

# ── App Tier ──────────────────────────────────────────────────────────────────
module "sg_app" {
  source = "./modules/security"

  name        = "${local.short_prefix}-app-sg"
  description = "App SG: solo acepta tráfico del Internal ALB"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.short_prefix}-app-sg" }

  ingress_rules = [
    {
      description     = "App traffic desde Internal ALB"
      from_port       = var.app_port
      to_port         = var.app_port
      protocol        = "tcp"
      security_groups = [module.sg_internal_alb.security_group_id]
    }
  ]
}

# =============================================================================
# 3. DYNAMODB — Global Table v2 (Activo-Activo con eu-west-1)
# La tabla se crea en eu-central-1 (provider default) con stream habilitado.
# El bloque `replica` replica todos los datos a eu-west-1 en tiempo real.
# IMPORTANTE: al ser Global Table, NO se usa provider = aws.ireland aquí.
# DynamoDB gestiona la replicación internamente.
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

  replica_regions                = [var.dr_region] # → eu-west-1
  point_in_time_recovery_enabled = var.dynamodb_pitr_enabled
  server_side_encryption_enabled = true
}

# =============================================================================
# 4. IAM ROLES — Fráncfort
# =============================================================================

# ── Web Role (SSM only) ───────────────────────────────────────────────────────
module "iam_web" {
  source = "./modules/iam"

  role_name             = "${var.project_prefix}-web-role"
  instance_profile_name = "${var.project_prefix}-web-instance-profile"
  assume_role_service   = "ec2.amazonaws.com"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

# ── App Role (SSM + DynamoDB least-privilege) ─────────────────────────────────
module "iam_app" {
  source = "./modules/iam"

  role_name             = "${var.project_prefix}-app-role"
  instance_profile_name = "${var.project_prefix}-app-instance-profile"
  assume_role_service   = "ec2.amazonaws.com"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]

  # Acceso R/W SOLO a la tabla específica — principio de mínimo privilegio
  # En Global Table: la misma política es válida para leer/escribir localmente;
  # la replicación entre regiones la gestiona DynamoDB de forma transparente.
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
# 5. INTERNAL ALB — Fráncfort (delante de la capa App)
#
# CRÍTICO: enable_cross_zone_load_balancing = false
#   Si está true, el Internal ALB distribuiría requests entre TODAS las instancias
#   App de todas las AZs. Esto rompería el experimento de Zonal Shift de la Fase 1:
#   si hacemos un shift de eu-central-1a, el tráfico debería limitarse a 1b y 1c,
#   pero con cross_zone=true seguiría llegando a instancias de 1a a través del ALB.
#
# enable_zonal_shift = false: Los ALBs internos no participan en ARC Zonal Shift
#   (el shift lo hace el ALB público externo).
# =============================================================================
module "internal_alb" {
  source = "./modules/alb"

  name               = "${local.short_prefix}-int-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.sg_internal_alb.security_group_id]

  internal                         = true
  enable_cross_zone_load_balancing = false # ← CRÍTICO para experimento Zonal Shift
  enable_zonal_shift               = false # No aplica en ALBs internos

  tg_port        = var.app_port
  tg_protocol    = "HTTP"
  tg_target_type = "instance"
  hc_path        = "/index.html" # La App responde con JSON en la raíz

  tags_lb = { Name = "${local.short_prefix}-int-alb" }
  tags_tg = { Name = "${local.short_prefix}-int-alb-tg" }
}

# =============================================================================
# 6. ALB PÚBLICO — Fráncfort (internet-facing, Zonal Shift habilitado)
# =============================================================================
module "alb" {
  source = "./modules/alb"

  name               = "${local.short_prefix}-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.sg_alb.security_group_id]

  internal                         = false
  enable_cross_zone_load_balancing = true
  enable_zonal_shift               = true # Fase 1: ARC Zonal Shift habilitado

  tg_port        = var.web_port
  tg_protocol    = "HTTP"
  tg_target_type = "instance"
  hc_path        = var.alb_health_check_path

  tags_lb = { Name = "${local.short_prefix}-alb" }
  tags_tg = { Name = "${local.short_prefix}-alb-tg" }
}

# =============================================================================
# 7. APP ASG — Fráncfort (desired=3, se registra en Internal ALB)
# Se crea ANTES del Web ASG para que el Internal ALB DNS esté disponible
# al renderizar el user_data de la capa Web.
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

  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    tier                 = "app"
    app_port             = var.app_port
    app_internal_alb_dns = "" # Unused en la rama app del template
  })

  additional_tags = { Tier = "App", Region = "Frankfurt" }
}

# =============================================================================
# 8. WEB ASG — Fráncfort (desired=3, se registra en ALB público)
# user_data apunta al DNS del Internal ALB (estable aunque cambien IPs de App)
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

  # Fase 2: se pasa el DNS del Internal ALB en lugar de una IP estática.
  # El DNS es inmutable durante la vida del Internal ALB.
  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    tier                 = "web"
    app_port             = var.app_port
    app_internal_alb_dns = module.internal_alb.alb_dns_name
  })

  additional_tags = { Tier = "Web", Region = "Frankfurt" }
}

# =============================================================================
# 9. AUTO RECOVERY (Fase 1 — Zonal Shift Closed-Loop, se mantiene sin cambios)
# =============================================================================
module "auto_recovery" {
  source = "./modules/auto_recovery"

  project_prefix     = var.project_prefix
  alb_arn            = module.alb.alb_arn
  alb_arn_suffix     = module.alb.alb_arn_suffix
  availability_zones = var.availability_zones
}

# =============================================================================
# ████████████████████  IRLANDA — WARM STANDBY  ███████████████████████████████
# Todos los recursos usan: provider = aws.ireland
# =============================================================================

# =============================================================================
# 10. VPC Irlanda
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
# 11. SECURITY GROUPS — Irlanda
# =============================================================================

module "sg_alb_ireland" {
  source    = "./modules/security"
  providers = { aws = aws.ireland }

  name        = "${local.short_prefix}-alb-sg-ie"
  description = "ALB SG Irlanda: permite HTTP/HTTPS desde internet"
  vpc_id      = module.vpc_ireland.vpc_id
  tags        = { Name = "${local.short_prefix}-alb-sg-ie" }

  ingress_rules = [
    { description = "HTTP", from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    { description = "HTTPS", from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  ]
}

module "sg_web_ireland" {
  source    = "./modules/security"
  providers = { aws = aws.ireland }

  name        = "${local.short_prefix}-web-sg-ie"
  description = "Web SG Irlanda: solo acepta tráfico del ALB público"
  vpc_id      = module.vpc_ireland.vpc_id
  tags        = { Name = "${local.short_prefix}-web-sg-ie" }

  ingress_rules = [
    {
      description     = "HTTP desde ALB público Irlanda"
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
  description = "Internal ALB SG Irlanda: acepta tráfico de Web en puerto app"
  vpc_id      = module.vpc_ireland.vpc_id
  tags        = { Name = "${local.short_prefix}-int-alb-sg-ie" }

  ingress_rules = [
    {
      description     = "App port desde Web tier Irlanda"
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
  description = "App SG Irlanda: solo acepta tráfico del Internal ALB"
  vpc_id      = module.vpc_ireland.vpc_id
  tags        = { Name = "${local.short_prefix}-app-sg-ie" }

  ingress_rules = [
    {
      description     = "App traffic desde Internal ALB Irlanda"
      from_port       = var.app_port
      to_port         = var.app_port
      protocol        = "tcp"
      security_groups = [module.sg_internal_alb_ireland.security_group_id]
    }
  ]
}

# =============================================================================
# 12. IAM ROLES — Irlanda
# Los roles IAM son globales pero se crean aquí con provider alias para que
# el instance profile quede en el contexto correcto de la región.
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

  # Acceso R/W a la réplica local de la Global Table (misma tabla, distinta réplica)
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
          # ARN de la réplica en Irlanda (misma tabla, región diferente)
          Resource = "arn:aws:dynamodb:${var.dr_region}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_name}"
        }
      ]
    })
  }
}

# =============================================================================
# 13. INTERNAL ALB — Irlanda (cross_zone=false, igual que Frankfurt)
# =============================================================================
module "internal_alb_ireland" {
  source    = "./modules/alb"
  providers = { aws = aws.ireland }

  name               = "${local.short_prefix}-int-alb-ie"
  vpc_id             = module.vpc_ireland.vpc_id
  subnet_ids         = module.vpc_ireland.private_subnet_ids
  security_group_ids = [module.sg_internal_alb_ireland.security_group_id]

  internal                         = true
  enable_cross_zone_load_balancing = false # Mismo razonamiento que Frankfurt
  enable_zonal_shift               = false

  tg_port        = var.app_port
  tg_protocol    = "HTTP"
  tg_target_type = "instance"
  hc_path        = "/index.html"

  tags_lb = { Name = "${local.short_prefix}-int-alb-ie" }
  tags_tg = { Name = "${local.short_prefix}-int-alb-tg-ie" }
}

# =============================================================================
# 14. ALB PÚBLICO — Irlanda (Zonal Shift ON, es el endpoint de failover)
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
# 15. APP ASG — Irlanda (Warm Standby: desired=1)
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

  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    tier                 = "app"
    app_port             = var.app_port
    app_internal_alb_dns = ""
  })

  additional_tags = { Tier = "App", Region = "Ireland" }
}

# =============================================================================
# 16. WEB ASG — Irlanda (Warm Standby: desired=1)
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

  user_data = templatefile("${path.module}/modules/compute/user_data.sh.tpl", {
    tier                 = "web"
    app_port             = var.app_port
    app_internal_alb_dns = module.internal_alb_ireland.alb_dns_name
  })

  additional_tags = { Tier = "Web", Region = "Ireland" }
}

# =============================================================================
# ████████████████████  ROUTE 53 — FAILOVER DNS  ██████████████████████████████
# Route 53 es global: no requiere provider alias, usa el provider default.
# =============================================================================

# =============================================================================
# 17. ROUTE 53 HEALTH CHECK
# Monitoriza el endpoint público de Fráncfort (/health.html).
# Si falla, Route 53 activa el registro SECONDARY (Irlanda) automáticamente.
# Nota: El ARC Region Switch Plan del Paso 3 puede manipular este health check
# para forzar el failover proactivamente (antes de que realmente falle).
# =============================================================================
resource "aws_route53_health_check" "frankfurt_alb" {
  # Dirección del ALB de Fráncfort — el DNS name resuelve a IPs en las 3 AZs
  fqdn              = module.alb.alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = var.alb_health_check_path
  failure_threshold = 3  # fallos consecutivos antes de declarar unhealthy
  request_interval  = 30 # segundos entre checks

  # Regiones de Route 53 que realizan el health check (multi-région para precisión)
  regions = ["eu-west-1", "us-east-1", "ap-southeast-1"]

  tags = {
    Name = "${var.project_prefix}-frankfurt-hc"
  }
}

# =============================================================================
# 18. REGISTRO DNS PRIMARY — Fráncfort (con health check asociado)
# Tipo ALIAS apunta al ALB de Fráncfort.
# Route 53 solo rutará aquí si el health check está healthy.
# =============================================================================
resource "aws_route53_record" "primary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  # Failover routing policy
  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "frankfurt-primary"
  health_check_id = aws_route53_health_check.frankfurt_alb.id

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# 19. REGISTRO DNS SECONDARY — Irlanda (failover automático)
# Si el health check de Fráncfort falla, todo el tráfico va a Irlanda.
# No tiene health check asociado (el SECONDARY nunca necesita health check).
# =============================================================================
resource "aws_route53_record" "secondary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "ireland-secondary"

  alias {
    name                   = module.alb_ireland.alb_dns_name
    zone_id                = module.alb_ireland.alb_zone_id
    evaluate_target_health = true
  }
}
# =============================================================================
# ARC REGION SWITCH PLAN
# =============================================================================

# =============================================================================
# 20. IAM ROLE - Execution Role del ARC Region Switch Plan
#
# El plan ARC necesita un rol con permisos para ejecutar los pasos del workflow:
#   - autoscaling:UpdateAutoScalingGroup -> Paso 1 (escalar ASGs Irlanda)
#   - route53:UpdateHealthCheck         -> Paso 2 (manipular health check)
# =============================================================================
data "aws_iam_policy_document" "arc_plan_assume_role" {
  statement {
    sid     = "AllowARCRegionSwitchAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["region-switch.arc.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "arc_execution_role" {
  name               = "${var.project_prefix}-arc-plan-execution-role"
  assume_role_policy = data.aws_iam_policy_document.arc_plan_assume_role.json

  tags = { Name = "${var.project_prefix}-arc-plan-execution-role" }
}

data "aws_iam_policy_document" "arc_plan_permissions" {
  # Paso 1: escalar los ASGs de Irlanda a capacidad de produccion
  statement {
    sid    = "AllowASGScaleUp"
    effect = "Allow"
    actions = [
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:DescribeAutoScalingGroups",
    ]
    resources = [
      module.app_asg_ireland.autoscaling_group_arn,
      module.web_asg_ireland.autoscaling_group_arn,
    ]
  }

  # Paso 2: manipular el health check para forzar el failover Route 53
  statement {
    sid    = "AllowRoute53HealthCheckUpdate"
    effect = "Allow"
    actions = [
      "route53:UpdateHealthCheck",
      "route53:GetHealthCheck",
    ]
    resources = [
      "arn:aws:route53:::healthcheck/${aws_route53_health_check.frankfurt_alb.id}"
    ]
  }
}

resource "aws_iam_role_policy" "arc_plan_permissions" {
  name   = "arc-region-switch-plan-policy"
  role   = aws_iam_role.arc_execution_role.id
  policy = data.aws_iam_policy_document.arc_plan_permissions.json
}

# =============================================================================
# 21. ARC REGION SWITCH PLAN - Core del TFG Fase 2
#
# Workflow - 2 pasos en secuencia:
#   Paso 1: escalar los ASGs de Irlanda antes de desviar trafico.
#   Paso 2: forzar failover de trafico via Route 53 Health Check.
# =============================================================================
resource "aws_arcregionswitch_plan" "main_dr_plan" {
  name              = "${var.project_prefix}-dr-plan"
  execution_role    = aws_iam_role.arc_execution_role.arn
  recovery_approach = "activePassive"

  regions = [var.aws_region, var.dr_region]

  workflow {
    workflow_target_action = "activate"

    # Paso 1: Escalar ASGs de Irlanda a capacidad de produccion
    step {
      name                 = "scale-up-ireland-asg"
      execution_block_type = "EC2AutoScaling"

      ec2_asg_capacity_increase_config {
        asg {
          arn = module.app_asg_ireland.autoscaling_group_arn
        }

        target_percent               = 300
        capacity_monitoring_approach = "sampledMaxInLast24Hours"
      }
    }

    # Paso 2: Forzar failover de trafico via Route 53 Health Check
    step {
      name                 = "failover-route53-traffic"
      execution_block_type = "Route53HealthCheck"

      route53_health_check_config {
        hosted_zone_id = data.aws_route53_zone.main.zone_id
        record_name    = var.domain_name
      }
    }
  }

  tags = {
    Name = "${var.project_prefix}-dr-plan"
  }

  depends_on = [
    aws_iam_role_policy.arc_plan_permissions,
    module.app_asg_ireland,
    module.web_asg_ireland,
    aws_route53_health_check.frankfurt_alb,
  ]
}
