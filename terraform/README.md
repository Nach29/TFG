# Terraform README

Esta carpeta contiene el despliegue completo de la plataforma del TFG.

## Contenido

- `providers.tf`: configuracion de provider AWS principal y alias de Irlanda.
- `data.tf`: data sources para AMIs, Hosted Zone e identidad AWS.
- `variables.tf`: variables de configuracion global.
- `main.tf`: orquestacion completa de networking, seguridad, compute, datos, DNS y ARC.
- `outputs.tf`: salidas utiles para demo y validacion.
- `bootstrap/`: backend remoto inicial para estado Terraform.
- `modules/`: modulos reutilizables del proyecto.

## Modulos

- `vpc`: VPC, subnets, IGW, NAT Gateway y route tables.
- `security`: security groups reutilizables con reglas declarativas.
- `iam`: roles e instance profiles con managed e inline policies.
- `compute`: launch templates, ASG y user data para Web y App.
- `alb`: ALB, target group y listener HTTP.
- `dynamodb`: tabla DynamoDB con soporte para Global Table.
- `auto_recovery`: Lambda + CloudWatch para ARC Zonal Shift.

## Flujo de despliegue

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

## Flujo de failover regional

El `aws_arcregionswitch_plan` implementa un workflow simple de 2 pasos:

1. Escalar los ASG de Irlanda.
2. Activar el failover DNS en Route 53.

## Notas de mantenimiento

- No habilitar `cross_zone_load_balancing` en el Internal ALB.
- Si cambias AMIs o `user_data`, revisa el comportamiento de `instance_refresh` en el modulo `compute`.
- El `desired_capacity` de los ASG ignora cambios externos para convivir con acciones del ARC plan.
- Antes de validar de verdad, ejecuta `terraform init`, ya que sin ello `terraform validate` no puede resolver modulos.
