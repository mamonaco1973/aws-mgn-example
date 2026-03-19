# =====================================================================================
# Terraform Providers
# =====================================================================================

terraform {
  required_providers {

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }

    tls = {
      source = "hashicorp/tls"
    }

    local = {
      source = "hashicorp/local"
    }

  }
}

# Configure the AzureRM provider
provider "azurerm" {
  features {}
}

# =====================================================================================
# Data Sources
# =====================================================================================

data "azurerm_subscription" "primary" {}

data "azurerm_client_config" "current" {}

# =====================================================================================
# SSH Key Generation
# =====================================================================================

resource "tls_private_key" "vm_key" {

  algorithm = "RSA"
  rsa_bits  = 4096

}

# Write private key to PEM file for later SSH usage
resource "local_file" "vm_key_pem" {

  filename        = "../${var.prefix}-vm.pem"
  content         = tls_private_key.vm_key.private_key_pem
  file_permission = "0600"

}

# =====================================================================================
# Resource Group
# =====================================================================================

resource "azurerm_resource_group" "main" {

  name     = "${var.prefix}-resource-group"
  location = var.location

}