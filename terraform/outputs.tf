output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the three public subnets (one per AZ)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the three private subnets (one per AZ)"
  value       = module.vpc.private_subnet_ids
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer — use this to access the app"
  value       = module.alb.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer (needed for ARC Zonal Shift)"
  value       = module.alb.alb_arn
}

output "web_instance_ids" {
  description = "EC2 Instance IDs for the Web tier (index = AZ index)"
  value       = module.web_instances[*].instance_id
}

output "web_instance_private_ips" {
  description = "Private IP addresses of the Web tier instances"
  value       = module.web_instances[*].private_ip
}

output "app_instance_ids" {
  description = "EC2 Instance IDs for the App tier (index = AZ index)"
  value       = module.app_instances[*].instance_id
}

output "app_instance_private_ips" {
  description = "Private IP addresses of the App tier instances"
  value       = module.app_instances[*].private_ip
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB sessions table"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB sessions table"
  value       = module.dynamodb.table_arn
}

output "web_iam_instance_profile" {
  description = "Name of the IAM instance profile attached to Web instances (SSM only)"
  value       = module.iam_web.instance_profile_name
}

output "app_iam_instance_profile" {
  description = "Name of the IAM instance profile attached to App instances (SSM + DynamoDB)"
  value       = module.iam_app.instance_profile_name
}
