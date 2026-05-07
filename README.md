# TFG - Resiliencia Cloud en AWS con Terraform

Proyecto de Trabajo de Fin de Grado centrado en resiliencia sobre AWS. El repositorio despliega una arquitectura web de tres capas gestionada 100% con Terraform y preparada para demostrar dos escenarios: fallo gris zonal con ARC Zonal Shift y desastre regional con failover desde Frankfurt a Irlanda.

![Architecture](Arquitectura-tfg.png)

## Objetivo

El objetivo del TFG es mostrar que una plataforma sencilla y contenida en costes puede incorporar mecanismos reales de resiliencia:

- Aislamiento automatico de una Availability Zone degradada.
- Failover regional orquestado hacia una region warm standby.
- Infraestructura reproducible y auditable mediante Terraform.
- Operacion segura sin SSH, usando solo SSM Session Manager.

## Arquitectura actual

Regiones:
- `eu-central-1` (Frankfurt): region activa.
- `eu-west-1` (Ireland): warm standby.

Camino de peticion:
- Internet -> Public ALB -> Web ASG -> Internal ALB -> App ASG -> DynamoDB Global Table.

Capas:
- Web: Apache + PHP en ASG privado.
- App: servidor HTTP Python en ASG privado.
- Datos: DynamoDB Global Table replicada entre Frankfurt e Irlanda.

DNS global:
- `dontpushthis.link` usa Route 53 Failover Routing.
- El registro `PRIMARY` apunta al ALB de Frankfurt.
- El registro `SECONDARY` apunta al ALB de Irlanda.

## Mecanismos de resiliencia

### 1. Fallo gris zonal

El ALB publico de Frankfurt tiene ARC Zonal Shift habilitado. El modulo `auto_recovery` crea una alarma de CloudWatch por AZ y una Lambda que inicia un zonal shift cuando detecta un pico de `HTTPCode_Target_5XX_Count`.

Puntos importantes del experimento:
- El Internal ALB mantiene `enable_cross_zone_load_balancing = false`.
- El objetivo es preservar el aislamiento por zona para que el experimento sea observable.
- Las instancias no exponen SSH; el acceso operativo se hace via SSM.

### 2. Desastre regional

El recurso `aws_arcregionswitch_plan` modela un failover activo-pasivo entre Frankfurt e Irlanda.

Workflow actual del plan:
1. Escalar el ASG de la capa App en Irlanda a capacidad de produccion.
2. Escalar el ASG de la capa Web en Irlanda a capacidad de produccion.
3. Forzar el failover DNS mediante el health check de Route 53.

La validacion intermedia de DynamoDB se elimino para reducir complejidad del TFG y dejar la demo mas directa.

## Restricciones de diseno

Estas decisiones forman parte del diseno del proyecto y se respetan en el codigo:

- FinOps: instancias `t3.micro` y un solo NAT Gateway por region.
- Least privilege: IAM granular y sin acceso SSH.
- Terraform AWS Provider `~> 6.38` para usar `aws_arcregionswitch_plan`.
- `enable_cross_zone_load_balancing = false` en el Internal ALB.

## Estructura del repositorio

```text
TFG/
|-- terraform/
|   |-- main.tf
|   |-- providers.tf
|   |-- variables.tf
|   |-- data.tf
|   |-- outputs.tf
|   |-- bootstrap/
|   `-- modules/
|       |-- alb/
|       |-- auto_recovery/
|       |-- compute/
|       |-- dynamodb/
|       |-- iam/
|       |-- security/
|       `-- vpc/
|-- Arquitectura-tfg.png
|-- reporte_fase2.md
|-- tester.py
`-- README.md
```

## Requisitos

- Terraform `>= 1.6.0`
- AWS CLI configurado con credenciales validas
- Permisos para EC2, VPC, ALB, IAM, Lambda, CloudWatch, Route 53, DynamoDB, SSM y ARC

## Despliegue rapido

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Una vez aplicado:
- El dominio publicado es `http://dontpushthis.link`
- Tambien puedes usar los outputs de Terraform para acceder a los ALB directamente

## Documentacion tecnica

La documentacion mas cercana al despliegue esta en:
- [terraform/README.md](terraform/README.md)
- [reporte_fase2.md](reporte_fase2.md)

## Estado del codigo

Tras la limpieza actual:
- Se ha retirado el modulo obsoleto de validacion ARC que ya no se usa.
- El `root` Terraform refleja el workflow real de 3 pasos del Region Switch Plan.
- La documentacion se ha alineado con la arquitectura activa del repositorio.

## Autor

Ignacio Colas Martin
Trabajo de Fin de Grado - 2026

