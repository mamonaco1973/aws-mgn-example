# ================================================================================
# Terraform Providers
#
# AWS is the only required provider for this phase. Version ~> 6.0 is pinned
# to avoid breaking changes from future major releases.
# ================================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ================================================================================
# Data Sources
#
# Resolves the list of available AZs at plan time so subnet resources can
# reference a concrete AZ without hard-coding region-specific names.
# ================================================================================

data "aws_availability_zones" "available" {
  state = "available"
}
