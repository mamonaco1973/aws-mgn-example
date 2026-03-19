# ================================================================================
# Virtual Network
#
# Provides the Layer-3 boundary for the Azure source environment.
# A /16 gives plenty of room for additional subnets without re-addressing.
# ================================================================================
resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# ================================================================================
# Subnet
#
# The source VM lives here. /24 is more than enough for a demo; the MGN
# agent talks outbound only, so no reserved address space is needed.
# ================================================================================
resource "azurerm_subnet" "main" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ================================================================================
# Network Security Group
#
# Allows inbound SSH (22) for agent installation and HTTP (80) to verify
# Apache is running before and after migration.
# ================================================================================
resource "azurerm_network_security_group" "main" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ==============================================================================
# Random suffix for VM prefix
# - Ensures each deployment produces a unique public DNS label
# - Stored in state so it does not change on every terraform apply
# ==============================================================================
resource "random_string" "vm_suffix" {
  length  = 6
  upper   = false
  special = false
}

# ================================================================================
# Public IP
#
# Dynamic allocation is sufficient for demo use. The DNS label combines the
# prefix with a random suffix to avoid conflicts across deployments in the
# same subscription.
# ================================================================================
resource "azurerm_public_ip" "main" {
  name                = "${var.prefix}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
  domain_name_label = "${var.prefix}-vm-${random_string.vm_suffix.result}"
}

# ================================================================================
# Network Interface
#
# Bridges the VM to the subnet and attaches the public IP so the MGN agent
# installer and SSH sessions can reach the VM from outside Azure.
# ================================================================================
resource "azurerm_network_interface" "main" {
  name                = "${var.prefix}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Associates the NSG with the NIC so security rules are enforced on the VM.
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}
