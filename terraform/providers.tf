# =============================================================================
# PROVIDERS
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31" # 5.31+ required for aws_lb enable_zonal_shift attribute
    }
  }
}

provider "aws" {
  region = var.aws_region

  # default_tags are automatically merged into every resource's tags block,
  # eliminating the need to repeat them in individual resources or modules.
  # Ref: https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags
  default_tags {
    tags = {
      Project   = "TFG"
      Owner     = "student-icolasma"
      ManagedBy = "Terraform"
    }
  }
}
