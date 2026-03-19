# ================================================================================
# Linux Virtual Machine
#
# Ubuntu 24.04 LTS source VM. Cloud-init (custom_data) installs Apache and
# downloads the AWS MGN agent installer so the VM is ready to register with
# the MGN service as soon as Phase 2 completes.
# ================================================================================
resource "azurerm_linux_virtual_machine" "main" {
  name                = "${var.prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.main.id
  ]

  # Password auth disabled — key-pair only, matching MGN agent install docs.
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.vm_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Ubuntu 24.04 LTS (Noble) — matches the OS tested with the MGN agent.
  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Runs once at first boot: installs Apache and fetches the MGN agent.
  custom_data = filebase64("scripts/custom_data.sh")
}

# ================================================================================
# Outputs
# ================================================================================

# Output the public FQDN
output "vm_public_fqdn" {
  value       = azurerm_public_ip.main.fqdn
  description = "The DNS name of the public IP address"
}
