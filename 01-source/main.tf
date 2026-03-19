# ================================================================================
# Provider Configuration
#
# AWS us-east-2 (source region) with TLS and local providers for SSH key
# generation and PEM file output.
# ================================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ================================================================================
# SSH Key Pair
#
# RSA 4096 key generated in Terraform state. Public half is registered with
# AWS as a key pair; private half is written to ../mgn-vm.pem for connect.sh
# and install_agent.sh.
# ================================================================================

resource "tls_private_key" "vm_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vm_key" {
  key_name   = "${var.prefix}-source-key"
  public_key = tls_private_key.vm_key.public_key_openssh
}

resource "local_sensitive_file" "vm_key_pem" {
  content         = tls_private_key.vm_key.private_key_pem
  filename        = "../mgn-vm.pem"
  file_permission = "0600"
}
