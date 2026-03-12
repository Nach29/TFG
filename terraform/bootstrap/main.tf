# =============================================================================
# BOOTSTRAP — Run ONCE before `terraform init` in the parent directory.
# Creates the S3 bucket and DynamoDB table used for remote state storage.
# Usage:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31" # 5.31+ required for ALB enable_zonal_shift
    }
  }
}

variable "aws_region" {
  description = "AWS region where bootstrap resources will be created"
  type        = string
  default     = "eu-west-1"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "TFG"
      Owner     = "student-icolasma"
      ManagedBy = "Terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# S3 bucket for Terraform state
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  # S3 bucket names must be globally unique and lowercase
  bucket = "tfg-student-icolasma-tfg-terraform-state"

  # Prevent accidental deletion of state
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "tfg-student-icolasma-tfg-terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# DynamoDB table for state locking
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "tfg-student-icolasma-tfg-terraform-lock"
  billing_mode = "PAY_PER_REQUEST" # On-demand — no minimum cost
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "tfg-student-icolasma-tfg-terraform-lock"
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "lock_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_lock.name
}

output "next_steps" {
  description = "Instructions for next steps"
  value       = "Run 'terraform init' then 'terraform apply' in the parent terraform/ directory"
}
