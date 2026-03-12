# =============================================================================
# DYNAMODB MODULE — outputs.tf
# =============================================================================

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN of the DynamoDB table (used to scope IAM policies for App instances)"
  value       = aws_dynamodb_table.this.arn
}

output "table_id" {
  description = "ID of the DynamoDB table (same as table_name for DynamoDB)"
  value       = aws_dynamodb_table.this.id
}
