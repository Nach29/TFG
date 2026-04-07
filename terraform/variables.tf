# =============================================================================
# ROOT VARIABLES — Fase 2: se añaden variables para Irlanda, ASG y dominio.
# Se mantienen los defaults más baratos/free-tier donde aplica.
# =============================================================================

# ── General ───────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "Región AWS principal (Fráncfort — activa)"
  type        = string
  default     = "eu-central-1"
}

variable "dr_region" {
  description = "Región AWS de Disaster Recovery (Irlanda — warm standby)"
  type        = string
  default     = "eu-west-1"
}

variable "project_prefix" {
  description = "Prefijo de nombre aplicado a todos los recursos. Convención: tfg-student-icolasma-TFG"
  type        = string
  default     = "tfg-student-icolasma-TFG"
}

variable "domain_name" {
  description = "Nombre del dominio raíz. La Hosted Zone debe existir previamente en Route 53."
  type        = string
  default     = "dontpushthis.link"
}

# ── Red — Fráncfort (eu-central-1) ───────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR del VPC principal (Fráncfort)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Exactamente 3 AZs de eu-central-1 para el despliegue activo"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs de subnets públicas en Fráncfort — uno por AZ (alineados por índice)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs de subnets privadas en Fráncfort — uno por AZ (alineados por índice)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

# ── Red — Irlanda (eu-west-1, Warm Standby) ───────────────────────────────────

variable "dr_vpc_cidr" {
  description = "CIDR del VPC de DR en Irlanda. Debe ser diferente al de Fráncfort para evitar solapamiento."
  type        = string
  default     = "10.1.0.0/16"
}

variable "dr_availability_zones" {
  description = "Exactamente 3 AZs de eu-west-1 para el despliegue standby"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "dr_public_subnet_cidrs" {
  description = "CIDRs de subnets públicas en Irlanda — uno por AZ"
  type        = list(string)
  default     = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
}

variable "dr_private_subnet_cidrs" {
  description = "CIDRs de subnets privadas en Irlanda — uno por AZ"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]
}

# ── EC2 / ASG — Compute ───────────────────────────────────────────────────────

variable "ami_id" {
  description = <<-EOT
    AMI ID para las instancias (Amazon Linux 2023).
    Cuando es null (default), se obtiene automáticamente desde AWS SSM Parameter Store.
    Anular solo para fijar una versión concreta de AMI.
  EOT
  type        = string
  default     = null
}

variable "web_instance_type" {
  description = "Tipo de instancia EC2 para la capa Web. t3.micro (~$0.0104/hr)."
  type        = string
  default     = "t3.micro"
}

variable "app_instance_type" {
  description = "Tipo de instancia EC2 para la capa App. t3.micro (~$0.0104/hr)."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Tamaño del volumen EBS raíz en GiB."
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Tipo del volumen EBS raíz. gp3 es más barato y rápido que gp2."
  type        = string
  default     = "gp3"
}

# ── ASG Capacidades — Fráncfort (Región Activa) ───────────────────────────────

variable "web_asg_desired" {
  description = "desired_capacity del ASG Web en Fráncfort (región activa)."
  type        = number
  default     = 3
}

variable "web_asg_min" {
  description = "min_size del ASG Web en Fráncfort."
  type        = number
  default     = 1
}

variable "web_asg_max" {
  description = "max_size del ASG Web en Fráncfort."
  type        = number
  default     = 6
}

variable "app_asg_desired" {
  description = "desired_capacity del ASG App en Fráncfort (región activa)."
  type        = number
  default     = 3
}

variable "app_asg_min" {
  description = "min_size del ASG App en Fráncfort."
  type        = number
  default     = 1
}

variable "app_asg_max" {
  description = "max_size del ASG App en Fráncfort."
  type        = number
  default     = 6
}

# ── ASG Capacidades — Irlanda (Warm Standby) ──────────────────────────────────

variable "dr_web_asg_desired" {
  description = "desired_capacity del ASG Web en Irlanda (warm standby = 1 instancia)."
  type        = number
  default     = 1
}

variable "dr_web_asg_min" {
  description = "min_size del ASG Web en Irlanda."
  type        = number
  default     = 1
}

variable "dr_web_asg_max" {
  description = "max_size del ASG Web en Irlanda (límite para el escalado del ARC Plan)."
  type        = number
  default     = 6
}

variable "dr_app_asg_desired" {
  description = "desired_capacity del ASG App en Irlanda (warm standby = 1 instancia)."
  type        = number
  default     = 1
}

variable "dr_app_asg_min" {
  description = "min_size del ASG App en Irlanda."
  type        = number
  default     = 1
}

variable "dr_app_asg_max" {
  description = "max_size del ASG App en Irlanda."
  type        = number
  default     = 6
}

# ── Puertos ───────────────────────────────────────────────────────────────────

variable "web_port" {
  description = "Puerto TCP en el que la capa Web sirve tráfico HTTP"
  type        = number
  default     = 80
}

variable "app_port" {
  description = "Puerto TCP en el que la capa App sirve tráfico HTTP"
  type        = number
  default     = 8080
}

# ── ALB ───────────────────────────────────────────────────────────────────────

variable "alb_listener_port" {
  description = "Puerto en el que el listener del ALB acepta tráfico"
  type        = number
  default     = 80
}

variable "alb_health_check_path" {
  description = "Ruta del health check del ALB. Apunta al archivo estático para el experimento de gray failure."
  type        = string
  default     = "/health.html"
}

variable "alb_idle_timeout" {
  description = "Timeout de conexión idle en segundos para el ALB"
  type        = number
  default     = 60
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────

variable "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB de sesiones (Global Table)"
  type        = string
  default     = "tfg-student-icolasma-TFG-sessions"
}

variable "dynamodb_hash_key" {
  description = "Nombre del atributo a usar como partition key (hash key)"
  type        = string
  default     = "sessionId"
}

variable "dynamodb_pitr_enabled" {
  description = "Habilitar Point-in-Time Recovery. Añade coste — desactivado por defecto en dev/demo."
  type        = bool
  default     = false
}
