# ================================================================================
# Terraform Providers
#
# Declares the AzureRM, TLS, and Local providers. TLS generates the VM
# SSH key pair in-state; Local writes the private key to disk for SSH use.
# ================================================================================

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

# ================================================================================
# Data Sources
#
# Pull subscription and tenant context so child resources can reference
# them without hard-coding IDs in variable defaults.
# ================================================================================

data "azurerm_subscription" "primary" {}

data "azurerm_client_config" "current" {}

# ================================================================================
# SSH Key Generation
#
# Generates an RSA 4096 key pair inside Terraform state. The public key is
# attached to the VM; the private key is written to a local PEM file used
# for post-deployment SSH access and MGN agent installation.
# ================================================================================

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

# ================================================================================
# Resource Group
#
# Single resource group scopes all Azure objects for this phase, making
# bulk teardown simple (destroy the group to remove everything).
# ================================================================================

resource "azurerm_resource_group" "main" {

  name     = "${var.prefix}-resource-group"
  location = var.location

}
