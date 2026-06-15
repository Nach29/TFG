# ANEXO C. Detalle de la implementación de la infraestructura y automatización

Código fuente de Terraform y automatización asociada

Durante el desarrollo del proyecto hemos construido la infraestructura mediante una configuración Terraform organizada por responsabilidades. En este anexo recogemos la estructura del código que utilizamos para desplegar la arquitectura, con especial atención a la carpeta `terraform/`, ya que en ella definimos la red, los balanceadores, los grupos de autoescalado, la tabla DynamoDB global, los permisos IAM y los mecanismos de recuperación automática y regional.

Organizamos el código para que cada componente pueda revisarse de forma aislada sin perder la visión completa del despliegue. El módulo raíz coordina la región activa de Frankfurt y la región de recuperación en Irlanda mediante providers diferenciados, mientras que los módulos reutilizables concentran las piezas repetidas de red, seguridad, balanceo, cómputo, datos, permisos y recuperación zonal. Dejamos los scripts Python como apoyo operativo: uno se empaqueta como función Lambda desde Terraform y el otro se utiliza como sonda de telemetría durante las pruebas.

## 1. Estructura del código

En el árbol siguiente mostramos los ficheros fuente relevantes. Omitimos los directorios generados por herramientas, como `.terraform/` y `__pycache__/`, porque no forman parte de la implementación mantenida manualmente.

```text
terraform/
|-- .terraform.lock.hcl
|-- data.tf
|-- main.tf
|-- outputs.tf
|-- providers.tf
|-- variables.tf
`-- modules/
    |-- alb/
    |   |-- main.tf
    |   |-- outputs.tf
    |   `-- variables.tf
    |-- auto_recovery/
    |   |-- main.tf
    |   |-- outputs.tf
    |   |-- variables.tf
    |   `-- lambda_src/
    |       `-- zonal_shift_handler.py
    |-- compute/
    |   |-- main.tf
    |   |-- outputs.tf
    |   |-- user_data.sh.tpl
    |   `-- variables.tf
    |-- dynamodb/
    |   |-- main.tf
    |   |-- outputs.tf
    |   `-- variables.tf
    |-- iam/
    |   |-- main.tf
    |   |-- outputs.tf
    |   `-- variables.tf
    |-- security/
    |   |-- main.tf
    |   |-- outputs.tf
    |   `-- variables.tf
    `-- vpc/
        |-- main.tf
        |-- outputs.tf
        `-- variables.tf
```

```text
scripts Python
|-- tester.py
`-- terraform/
    `-- modules/
        `-- auto_recovery/
            `-- lambda_src/
                `-- zonal_shift_handler.py
```

| Elemento | Función | Relevancia en la memoria |
|---|---|---|
| `terraform/` | Directorio principal de infraestructura como código. Contiene el módulo raíz y los módulos reutilizables del despliegue. | Permite revisar la arquitectura completa desde una única entrada y separa la definición de infraestructura de los scripts auxiliares. |
| `.terraform.lock.hcl` | Bloquea las versiones resueltas de los providers utilizados por Terraform. | Mejora la reproducibilidad del despliegue y evita cambios implícitos en los plugins entre ejecuciones. |
| `providers.tf` | Declara Terraform `>= 1.6.0`, el provider `hashicorp/aws` `~> 6.38`, el provider `hashicorp/archive` `~> 2.4`, el provider AWS principal en `eu-central-1` y el alias `aws.ireland` en `eu-west-1`. | Refleja la separación real entre Frankfurt como región activa e Irlanda como región warm standby, además de permitir el empaquetado de la Lambda de recuperación automática. |
| `data.tf` | Consulta la AMI de Amazon Linux 2023 desde SSM Parameter Store en Frankfurt e Irlanda, la zona pública de Route 53 y la identidad de la cuenta AWS. | Evita fijar manualmente AMIs regionales y permite construir ARNs y registros DNS con datos reales de la cuenta. |
| `variables.tf` | Centraliza regiones, CIDR, zonas de disponibilidad, tamaños de Auto Scaling, puertos, health checks y nombres de DynamoDB. | Deja explícitos los parámetros del entorno: `eu-central-1`, `eu-west-1`, capacidad activa de tres instancias por capa y capacidad warm standby de una instancia por capa. |
| `main.tf` | Orquesta el despliegue completo: VPCs, Security Groups, ALBs, ASGs, DynamoDB Global Table, Route 53 failover, recuperación zonal y plan `aws_arcregionswitch_plan.main_dr_plan`. | Es el punto principal para entender el flujo `Internet -> Public ALB -> Web ASG -> Internal ALB -> App ASG -> DynamoDB` y la estrategia activa/pasiva entre regiones. |
| `outputs.tf` | Publica identificadores y endpoints: VPCs, DNS de ALBs públicos e internos, ARNs de ASG, tabla DynamoDB, URL del servicio y plan de ARC Region Switch. | Facilita validar el despliegue y reutilizar los valores relevantes en pruebas, documentación y operación. |
| `modules/vpc/` | Crea una VPC, un Internet Gateway, tres subredes públicas, tres subredes privadas, una Elastic IP, un NAT Gateway y tablas de rutas. | Define la base de red que se reutiliza tanto en Frankfurt como en Irlanda, manteniendo una subred por zona de disponibilidad. |
| `modules/security/` | Crea Security Groups y reglas separadas para entradas y salidas, tanto por CIDR como por Security Group origen. | Implementa el aislamiento entre ALB público, capa web, ALB interno y capa de aplicación sin abrir tráfico innecesario. |
| `modules/alb/` | Crea el Application Load Balancer, su Target Group y el listener HTTP. Soporta modo público e interno mediante variables. | Permite distinguir el ALB público con Zonal Shift habilitado y el ALB interno con cross-zone deshabilitado para que el experimento zonal sea observable. |
| `modules/compute/` | Sustituye instancias sueltas por Launch Templates y Auto Scaling Groups, con IMDSv2 obligatorio, volumen raíz cifrado, health checks ELB e instance refresh. | Materializa las capas Web y App como capacidad gestionada, compatible con sustitución automática y con escalado durante Region Switch. |
| `modules/compute/user_data.sh.tpl` | Genera el arranque de las instancias. La rama Web instala Apache/PHP y consulta el ALB interno; la rama App levanta un servidor Python que devuelve estado, instancia y AZ. | Conecta el comportamiento observable de la aplicación con la infraestructura desplegada y permite medir fallos de capa App desde la capa Web. |
| `modules/dynamodb/` | Crea la tabla `tfg-student-icolasma-TFG-sessions` en modo `PAY_PER_REQUEST`, con streams, cifrado y réplica global en `eu-west-1`. | Aporta continuidad de datos entre regiones sin depender de servidores de base de datos administrados por el proyecto. |
| `modules/iam/` | Crea roles IAM, adjuntos de políticas gestionadas, políticas inline e instance profiles para EC2. | Aplica acceso por mínimo privilegio: SSM para administración sin SSH y permisos específicos de DynamoDB para la capa App. |
| `modules/auto_recovery/` | Empaqueta la Lambda con `archive_file`, crea su rol, logs, permisos de ARC Zonal Shift y alarmas CloudWatch 5XX por zona de disponibilidad. | Implementa el bucle cerrado `CloudWatch Alarm -> Lambda -> ARC Zonal Shift` para retirar tráfico de una AZ degradada. |
| `modules/*/variables.tf` | Define las entradas propias de cada módulo, como CIDR, subredes, reglas de seguridad, parámetros de ALB, capacidades de ASG y tiempos de alarma. | Hace explícitos los contratos entre el módulo raíz y cada pieza reutilizable del despliegue. |
| `modules/*/outputs.tf` | Devuelve identificadores usados por otros módulos, como IDs de VPC y subredes, Security Groups, DNS y ARNs de ALB, ARNs de ASG y ARN de DynamoDB. | Permite encadenar recursos sin duplicar valores ni introducir dependencias manuales fuera de Terraform. |
| `zonal_shift_handler.py` | Handler de Lambda que valida el estado `ALARM`, extrae la `AvailabilityZone` del evento de CloudWatch, traduce el nombre de AZ a AZ ID y ejecuta `StartZonalShift`. | Automatiza la respuesta ante picos de errores 5XX en una zona concreta y deja la duración de la retirada controlada por Terraform. |
| `tester.py` | Sonda de telemetría que envía peticiones HTTP al dominio público, extrae región, Web AZ y App AZ de la respuesta, calcula el RTO observado y exporta un CSV. | Se utiliza en las pruebas para comprobar si el tráfico deja de servirse desde la AZ degradada y para registrar el comportamiento del sistema durante la recuperación. |
