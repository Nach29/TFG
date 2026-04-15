# Reporte Fase 2 — Disaster Recovery Warm Standby + ARC Region Switch Plan

**TFG · Ignacio Colas Martín**  └─ Paso 2: ARC marca health check Frankfurt como FAILED
             Route53 activa SECONDARY → ALB Irlanda
             Usuarios ahora sirven desde Irlanda

POST-FAILOVER:
  Usuario → dontpushthis.link → Route53 SECONDARY → ALB Irlanda
            Irlanda: Web ASG (×3) → Internal ALB → App ASG (×3) → DynamoDB (réplica)
```




