# Reporte Fase 2 — Disaster Recovery Warm Standby + ARC Region Switch Plan

**TFG · Ignacio Colas Martín**  
**Fecha de generación:** Abril 2026  
**Para:** Tutor Arquitecto — Validación previa a `terraform apply`

---

## 1. Resumen Ejecutivo

La Fase 2 implementa una arquitectura de **Disaster Recovery Warm Standby** en Irlanda (`eu-west-1`) sobre la base de Fráncfort (`eu-central-1`) de la Fase 1. El cambio introduce cinco áreas de modificación:

| # | Área | Tipo | Impacto |
|---|------|------|---------|
| 1 | Módulo `compute` | Refactorización completa | Destructivo (EC2 → ASG) |
| 2 | Módulo `dynamodb` | Extensión | No destructivo (añade réplica) |
| 3 | Módulo `alb` | Extensión | No destructivo (nuevas variables) |
| 4 | Infraestructura Irlanda | Nuevo | N/A (recursos nuevos) |
| 5 | ARC Region Switch Plan | Nuevo | N/A (recursos nuevos) |

---

## 2. Archivos Modificados

### 2.1 `terraform/providers.tf`

**Cambio:** Actualización de versión + nuevo provider alias.

```hcl
# ANTES
version = "~> 5.31"
# Un solo provider: aws { region = "eu-central-1" }

# DESPUÉS
version = "~> 6.38"   # v6 requerido para aws_arcregionswitch_plan nativo (ARC Region Switch)
provider "aws" { region = "eu-central-1" }          # Provider principal
provider "aws" { alias = "ireland", region = "eu-west-1" }  # Warm Standby
```

**Justificación:** `aws_arcregionswitch_plan` es un recurso nativo disponible exclusivamente en el provider **v6** (~6.x). El alias `aws.ireland` permite desplegar recursos en Irlanda sin módulos separados. Además, se han añadido bloques `required_providers` a todos los módulos locales (`vpc`, `security`, etc.) para asegurar el correcto pase de alias de provider (`aws = aws.ireland`).

---

### 2.2 `terraform/data.tf`

Tres nuevas fuentes de datos:

| Data Source | Propósito |
|-------------|-----------|
| `aws_ssm_parameter.amazon_linux_2023_ireland` | AMI AL2023 en eu-west-1 (distinta por región) |
| `aws_route53_zone.main` | Recupera la Hosted Zone de `dontpushthis.link` |
| `aws_caller_identity.current` | Account ID para construir ARNs en políticas IAM |

---

### 2.3 `terraform/variables.tf`

Variables añadidas (las de Fase 1 se mantienen intactas):

| Variable | Valor Default | Descripción |
|----------|---------------|-------------|
| `dr_region` | `eu-west-1` | Región DR |
| `domain_name` | `dontpushthis.link` | Dominio Route53 |
| `dr_vpc_cidr` | `10.1.0.0/16` | CIDR VPC Irlanda (sin solapamiento con 10.0.0.0/16) |
| `dr_availability_zones` | `[eu-west-1a/b/c]` | AZs de Irlanda |
| `web_asg_desired` / `app_asg_desired` | `3` | Capacidad activa Frankfurt |
| `dr_web_asg_desired` / `dr_app_asg_desired` | `1` | Warm standby Irlanda |

---

### 2.4 `modules/compute/main.tf` ← CAMBIO DESTRUCTIVO

**Antes:** `aws_instance` (instancia única, IP estática).  
**Después:** `aws_launch_template` + `aws_autoscaling_group`.

```
aws_launch_template.this
  ├── IMDSv2 obligatorio (http_tokens = "required")
  ├── EBS gp3 cifrado (encrypted = true)
  ├── Sin SSH — acceso SSM únicamente
  └── Tag propagation a instancias y volúmenes

aws_autoscaling_group.this
  ├── vpc_zone_identifier = var.subnet_ids (multi-AZ)
  ├── desired_capacity    = var.desired_capacity (3 Frankfurt / 1 Irlanda)
  ├── target_group_arns   = var.target_group_arns (registro automático en ALB)
  ├── health_check_type   = "ELB" (más preciso que EC2)
  └── ignore_changes      = [desired_capacity] (el ARC Plan puede modificarlo)
```

> **IMPORTANTE para el Tutor**: El campo `ignore_changes = [desired_capacity]` es deliberado. El ARC Region Switch Plan escala el ASG de Irlanda de 1 a 3 durante el failover. Sin este `ignore_changes`, el siguiente `terraform plan` detectaría la divergencia y propendría revertir el ASG a su valor declarado (1), lo que destruiría las instancias recién escaladas.

---

### 2.5 `modules/compute/user_data.sh.tpl`

**Cambio crítico en la capa Web:**

```bash
# ANTES (Fase 1): IP estática de la instancia App de la misma AZ
$app_url = "http://${app_private_ip}:${app_port}";

# AHORA (Fase 2): DNS del Internal ALB (estable aunque cambien IPs en el ASG)
$app_url = "http://${app_internal_alb_dns}:${app_port}";
```

**Razón:** Con ASG, las instancias se crean y destruyen continuamente. Sus IPs privadas son efímeras. El DNS del Internal ALB es el punto estable que abstrae el pool de instancias App.

---

### 2.6 `modules/alb/main.tf` y `variables.tf`

Variables parametrizadas:

| Variable | Frankfurt externo | Internal ALB |
|----------|------------------|--------------|
| `internal` | `false` | `true` |
| `enable_cross_zone_load_balancing` | `true` | **`false`** ← CRÍTICO |
| `enable_zonal_shift` | `true` | `false` |

> **Explicación `enable_cross_zone_load_balancing = false` en Internal ALB:**  
> Este atributo es el punto más crítico de la Fase 2 para el experimento de Zonal Shift.  
> Si estuviera en `true`, el Internal ALB distribuiría las peticiones de la capa Web entre instancias App de **todas** las AZs. Cuando se activa un Zonal Shift sobre eu-central-1a, el ALB público deja de enviar tráfico web a la instancia Web de 1a, pero si el Internal ALB tiene cross_zone=true, la instancia Web de 1b seguiría enviando peticiones a la instancia App de 1a (que está en la zona "dañada"). Con `cross_zone=false`, el tráfico permanece completamente confinado por zona, logrando el aislamiento que el experimento requiere.

---

### 2.7 `modules/dynamodb/main.tf` y `variables.tf`

```hcl
# Cambios añadidos al recurso aws_dynamodb_table:
stream_enabled   = true                    # OBLIGATORIO para Global Tables
stream_view_type = "NEW_AND_OLD_IMAGES"    # Necesario para replicar updates/deletes

dynamic "replica" {
  for_each = var.replica_regions           # ["eu-west-1"]
  content {
    region_name = replica.value
  }
}
```

**Cómo funciona:** DynamoDB Global Tables v2 usa los streams para replicar cada operación de escritura a todas las réplicas en tiempo real. La latencia típica de replicación es < 1 segundo (la Lambda del Paso 2 verifica que sea < 2000ms para garantizar consistencia suficiente antes del failover).

---

## 3. Archivos Nuevos

### 3.1 `modules/arc_validation_lambda/`

Nuevo módulo compuesto por:

| Archivo | Contenido |
|---------|-----------|
| `lambda_src/validate_replication.py` | Handler Python 3.12 que consulta CloudWatch |
| `main.tf` | IAM Role, archive_file, aws_lambda_function, resource policy |
| `variables.tf` | table_name, target_region, max_latency_ms, etc. |
| `outputs.tf` | lambda_arn (referenciado en el ARC Plan) |

**Lógica de la Lambda:**
```python
# Consulta: max(ReplicationLatency) de los últimos 5 minutos
# Condición de éxito: latency_ms <= 2000
# En caso de fallo: raise ValueError()  → detiene el ARC Plan
```

---

### 3.2 Infraestructura de Irlanda (todo en `main.tf`, `provider = aws.ireland`)

| Recurso | Nombre | Capacidad |
|---------|--------|-----------|
| VPC | `tfg-student-icolasma-TFG-ireland-vpc` | 10.1.0.0/16 |
| ALB Público | `tfg-icolasma-alb-ie` | Internet-facing, Zonal Shift ON |
| Internal ALB | `tfg-icolasma-int-alb-ie` | cross_zone=false |
| Web ASG | `tfg-student-icolasma-TFG-web-ie-asg-*` | **desired=1** (standby) |
| App ASG | `tfg-student-icolasma-TFG-app-ie-asg-*` | **desired=1** (standby) |
| IAM Roles | `-web-role-ie`, `-app-role-ie` | SSM + DynamoDB |
| SGs | 4 SGs (alb, web, internal-alb, app) | Misma topología que Frankfurt |

---

### 3.3 Route 53 Failover (en `main.tf`, provider global)

```
dontpushthis.link  →  PRIMARY   (ALIAS → ALB Frankfurt)  [con health check]
                       SECONDARY (ALIAS → ALB Irlanda)    [sin health check]
```

**Health Check configurado:**
- Destino: DNS del ALB Frankfurt, puerto 80, ruta `/health.html`
- `failure_threshold = 3` + `request_interval = 30s`
- Regiones de check: eu-west-1, us-east-1, ap-southeast-1

---

## 4. El ARC Region Switch Plan — Detalle Técnico y Migración a Terraform v6

La implementación del Region Switch Plan supuso un reto, ya que este recurso fue introducido muy recientemente en Terraform y es completamente diferente a la sintaxis del CLI. Se tuvo que **actualizar todo el esquema AWS a la rama 6.x** e inyectar validaciones más robustas solicitadas por este schema de v6.

```hcl
resource "aws_arcregionswitch_plan" "main_dr_plan" {
  name              = "tfg-student-icolasma-TFG-dr-plan"
  execution_role    = aws_iam_role.arc_execution_role.arn
  recovery_approach = "activePassive"
  regions           = ["eu-central-1", "eu-west-1"]

  workflow {
    workflow_target_action = "activate" # Objetivo explícito del workflow (requerido en v6)
    ...
}
```

### Paso 1 — Escalado Pre-Tráfico (`ec2_asg_capacity_increase_config`)

```hcl
step {
  name                 = "scale-up-ireland-asg"
  execution_block_type = "EC2AutoScaling"

  ec2_asg_capacity_increase_config {
    asg { arn = <ARN del App ASG de Irlanda> }
    target_percent               = 300   # 1 instancia × 300% = 3 instancias
    capacity_monitoring_approach = "sampledMaxInLast24Hours" # Obligatorio indicar método en v6
  }
}
```

**Por qué primero:** Si escaláramos después del desvío de tráfico, habría un período donde Irlanda recibe carga de producción con solo 1 instancia. El escalado preventivo elimina ese riesgo.

### Paso 2 — Validación de Datos (`custom_action_lambda_config`)

```hcl
step {
  name                 = "validate-dynamodb-replication"
  execution_block_type = "CustomActionLambda"

  custom_action_lambda_config {
    region_to_run          = "activatingRegion"  # se ejecuta en eu-west-1
    retry_interval_minutes = 2
    timeout_minutes        = 10
    lambda { arn = <ARN Lambda de validación> }
  }
}
```

**Por qué en el medio:** Es el "gate" de seguridad de datos. Si la replicación está atrasada, el tráfico podría llegar a Irlanda con datos obsoletos. El plan se detiene automáticamente si la Lambda falla (lanza una excepción en Python).

### Paso 3 — Failover de Tráfico (`route53_health_check_config`)

```hcl
step {
  name                 = "failover-route53-traffic"
  execution_block_type = "Route53HealthCheck"

  route53_health_check_config {
    # Novedad v6: se referencia al dominio directamente en vez del ID del health_check
    hosted_zone_id = <ID de la Hosted Zone>
    record_name    = var.domain_name
  }
}
```

**Cómo funciona:** ARC manipula el estado de salud subyacente para forzar el failover. Route 53 detecta el fallo (en base a la zona y record que se le indica en este paso) y activa el registro SECONDARY que apunta al ALB de Irlanda.

### IAM Role del Plan (Least Privilege)

El `execution_role` tiene permisos **exactamente** para los 3 pasos:

```
autoscaling:UpdateAutoScalingGroup  → solo los 2 ASGs de Irlanda
lambda:InvokeFunction               → solo la Lambda de validación
route53:UpdateHealthCheck           → solo el health check de Frankfurt
```

---

## 5. Inventario de Recursos Nuevos

| Tipo | Cantidad | Descripción |
|------|----------|-------------|
| `aws_launch_template` | 4 (2 Frankfurt + 2 Irlanda) | Reemplaza las 6 `aws_instance` |
| `aws_autoscaling_group` | 4 | Web/App × 2 regiones |
| `aws_lb` (internal) | 2 | Internal ALB Frankfurt + Irlanda |
| `aws_lb` (public) | 1 | ALB Irlanda (Frankfurt ya existía) |
| `aws_lb_target_group` | 4 | TG por cada ALB (internal + public ×2) |
| `aws_vpc` | 1 | VPC Irlanda |
| `aws_subnet` | 6 | 3 pública + 3 privada Irlanda |
| `aws_nat_gateway` | 1 | NAT Irlanda |
| `aws_iam_role` | 4 | Web-ie, App-ie, ARC Exec, Lambda Validation |
| `aws_route53_health_check` | 1 | Frankfurt ALB monitor |
| `aws_route53_record` | 2 | PRIMARY + SECONDARY failover |
| `aws_lambda_function` | 1 | Validación DynamoDB |
| `aws_arcregionswitch_plan` | 1 | **El core del TFG Fase 2** |
| **Total nuevos** | **~60 recursos** | (aprox, incluyendo SGs y dependencias) |

---

## 6. Recursos Eliminados (Cambio Destructivo)

| Tipo | Cantidad | Causa |
|------|----------|-------|
| `aws_instance` | 6 | Reemplazadas por ASG + Launch Template |
| `aws_lb_target_group_attachment` | 3 | El ASG se registra automáticamente |

---

## 7. Comandos para Validación

```bash
cd /home/icolasma/TFG/terraform

# Paso 1: Inicializar y asegurar uso del plugin v6.x
terraform init -upgrade

# Paso 2: Validar sintaxis HCL (debe dar 0 errores)
terraform validate

# Paso 3: Revisar el plan completo ANTES de aplicar
terraform plan -out=fase2.plan

# Paso 4 (solo tras aprobación del tutor): aplicar
terraform apply fase2.plan
```

> **Nota de planificación:** El `terraform plan` mostrará ~60-70 recursos a crear y 9 a destruir (6 instancias + 3 attachments). El tiempo estimado de `apply` es 15-25 minutos (la réplica DynamoDB puede tardar varios minutos en propagarse a Irlanda).

---

## 8. Flujo de Failover Completo (para la demo del TFG)

```
NORMAL:
  Usuario → dontpushthis.link → Route53 PRIMARY → ALB Frankfurt
            Frankfurt: Web ASG (×3) → Internal ALB → App ASG (×3) → DynamoDB

TRIGGER FAILOVER (ejecutar el ARC Plan):
  ARC Plan START
  │
  ├─ Paso 1: scale App ASG Irlanda 1 → 3 (espera ELB health check)
  │
  ├─ Paso 2: Lambda verifica ReplicationLatency < 2000ms
  │    ├─ OK  → continúa
  │    └─ KO  → STOP (operador revisa y reintenta)
  │
  └─ Paso 3: ARC marca health check Frankfurt como FAILED
             Route53 activa SECONDARY → ALB Irlanda
             Usuarios ahora sirven desde Irlanda

POST-FAILOVER:
  Usuario → dontpushthis.link → Route53 SECONDARY → ALB Irlanda
            Irlanda: Web ASG (×3) → Internal ALB → App ASG (×3) → DynamoDB (réplica)
```
