provider "azurerm" {
  features {}
}

provider "tls" {}

# Generate an RSA SSH key
resource "tls_private_key" "myprivatekey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key locally
resource "local_file" "private_key" {
  content  = tls_private_key.myprivatekey.private_key_openssh
  filename = "${path.module}/private_key.openssh"
}

# Save the public key locally
resource "local_file" "public_key" {
  content  = tls_private_key.myprivatekey.public_key_openssh
  filename = "${path.module}/public_key.pub"
}

# Resource group
resource "azurerm_resource_group" "my_rg" {
  name     = "MyResourceGroup"
  location = "East US"
}

# Virtual network
resource "azurerm_virtual_network" "my_vnet" {
  name                = "MyVNet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name
}

# Subnet
resource "azurerm_subnet" "my_subnet" {
  name                 = "MySubnet"
  resource_group_name  = azurerm_resource_group.my_rg.name
  virtual_network_name = azurerm_virtual_network.my_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Network Security Group to allow SSH
resource "azurerm_network_security_group" "my_nsg" {
  name                = "MyNSG"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP address
resource "azurerm_public_ip" "my_public_ip" {
  name                = "MyPublicIP"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name
  allocation_method   = "Dynamic"
}

# Network Interface
resource "azurerm_network_interface" "my_nic" {
  name                = "MyNIC"
  location            = azurerm_resource_group.my_rg.location
  resource_group_name = azurerm_resource_group.my_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.my_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.my_public_ip.id
  }
}

# Associate NSG to NIC
resource "azurerm_network_interface_security_group_association" "myprivatekey" {
  network_interface_id      = azurerm_network_interface.my_nic.id
  network_security_group_id = azurerm_network_security_group.my_nsg.id
}

# Virtual Machine
resource "azurerm_virtual_machine" "my_vm" {
  name                  = "MyVM"
  location              = azurerm_resource_group.my_rg.location
  resource_group_name   = azurerm_resource_group.my_rg.name
  network_interface_ids = [azurerm_network_interface.my_nic.id]
  vm_size               = "Standard_DS1_v2"

  # Create the VM with an image from the marketplace
  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Define the OS disk
  storage_os_disk {
    name              = "myosdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  # Computer name, admin username
  os_profile {
    computer_name  = "myvm"
    admin_username = "adminuser"
  }

  # SSH Key for the VM
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/adminuser/.ssh/authorized_keys"
      key_data = tls_private_key.myprivatekey.public_key_openssh
    }
  }
}
