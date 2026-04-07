# =============================================================================
# COMPUTE MODULE — variables.tf  (Fase 2: variables para ASG + Launch Template)
# =============================================================================

variable "name_prefix" {
  description = "Prefijo para nombrar el Launch Template y el ASG (e.g. 'tfg-web-frankfurt')"
  type        = string
}

variable "ami_id" {
  description = "AMI ID para el Launch Template (Amazon Linux 2023 recomendado)"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instancia EC2 usado en el Launch Template"
  type        = string
  default     = "t3.micro"
}

variable "subnet_ids" {
  description = "Lista de IDs de subnets privadas donde el ASG desplegará instancias (multi-AZ)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Lista de IDs de Security Groups a asociar a cada instancia lanzada"
  type        = list(string)
}

variable "iam_instance_profile_name" {
  description = "Nombre del IAM Instance Profile a adjuntar (SSM + permisos de la capa)"
  type        = string
}

variable "root_volume_size" {
  description = "Tamaño del volumen EBS raíz en GiB"
  type        = number
  default     = 8
}

variable "root_volume_type" {
  description = "Tipo del volumen EBS raíz. gp3 es más barato y rápido que gp2."
  type        = string
  default     = "gp3"
}

variable "user_data" {
  description = "Script de user data como cadena ya renderizada. Se codificará en base64 internamente. Null desactiva user data."
  type        = string
  default     = null
}

variable "desired_capacity" {
  description = "Número deseado de instancias en el ASG. Frankfurt: 3, Irlanda: 1."
  type        = number
  default     = 1
}

variable "min_size" {
  description = "Número mínimo de instancias que el ASG mantendrá siempre activas"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Número máximo de instancias que el ASG puede escalar"
  type        = number
  default     = 6
}

variable "target_group_arns" {
  description = "Lista de ARNs de ALB Target Groups en los que el ASG registrará automáticamente sus instancias"
  type        = list(string)
  default     = []
}

variable "additional_tags" {
  description = "Tags adicionales a fusionar en el Launch Template y propagar a las instancias"
  type        = map(string)
  default     = {}
}
