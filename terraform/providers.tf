# =============================================================================
# Providers
#
# AWS provider v6 is required because the project uses the native
# aws_arcregionswitch_plan resource.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.38"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Frankfurt is the active region.
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

# Ireland is the warm standby region.
provider "aws" {
  alias  = "ireland"
  region = var.dr_region

  default_tags {
    tags = {
      Project   = "TFG"
      Owner     = "student-icolasma"
      ManagedBy = "Terraform"
      Role      = "WarmStandby"
    }
  }
}
