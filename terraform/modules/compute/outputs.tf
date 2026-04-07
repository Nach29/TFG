# =============================================================================
# COMPUTE MODULE — outputs.tf  (Fase 2: outputs del ASG y Launch Template)
# =============================================================================

output "autoscaling_group_arn" {
  description = "ARN del Auto Scaling Group — usado por el ARC Region Switch Plan para escalar capacidad"
  value       = aws_autoscaling_group.this.arn
}

output "autoscaling_group_name" {
  description = "Nombre del Auto Scaling Group — usado para referencias en CloudWatch y políticas de escalado"
  value       = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  description = "ID del Launch Template — útil para actualizaciones de AMI y debugging"
  value       = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  description = "Última versión del Launch Template disponible"
  value       = aws_launch_template.this.latest_version
}
