# =============================================================================
# ARC VALIDATION LAMBDA MODULE — outputs.tf
# =============================================================================

output "lambda_arn" {
  description = "ARN de la Lambda de validación — referenciado en el bloque custom_action_lambda_config del aws_arcregionswitch_plan"
  value       = aws_lambda_function.validate_replication.arn
}

output "lambda_function_name" {
  description = "Nombre de la Lambda de validación"
  value       = aws_lambda_function.validate_replication.function_name
}
