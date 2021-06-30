variable "prefix" {
  type = string
  default = "rocketChat"
  description = "Overall name for the installation - resource names are prefixed with this"
}

variable "location" {
  type = string
  default = "westus2"
  description = "Azure location to install resources into"
}

variable "admin_username" {
  type = string
  default = "rocket"
  description = "Administrator user name for virtual machine"
}

variable "vm_size" {
  type = string
  # Recommend something with ~3GB+ of RAM at a minimum
  default = "Standard_DS1_v2"
  description = "VM size (one of https://docs.microsoft.com/en-us/azure/templates/microsoft.compute/virtualmachines#HardwareProfile)"
}

variable "ssh_public_key_file" {
  type = string
  description = "Location of SSH public key file for authentication to the VM"
}

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}RG"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
    name                = "${var.prefix}VNet"
    address_space       = ["10.0.0.0/16"]
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}Subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IP
resource "azurerm_public_ip" "publicip" {
  name                = "${var.prefix}PublicIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}


# Create Network Security Group and rule
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.prefix}NSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

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
  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate security group with subnet
resource "azurerm_subnet_network_security_group_association" "subnetNSG" {
  subnet_id = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create network interface
resource "azurerm_network_interface" "nic" {
  name                      = "${var.prefix}NIC"
  location                  = azurerm_resource_group.rg.location
  resource_group_name       = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "${var.prefix}NICConfg"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip.id
  }
}

# Create a Linux virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "${var.prefix}VM"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.nic.id]
  size               = var.vm_size

  admin_username = var.admin_username

  admin_ssh_key {
    username = var.admin_username
    public_key = file(var.ssh_public_key_file)
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
    disk_size_gb = 30
  }
}

# Create and mount a data disk to the VM
resource "azurerm_managed_disk" "vmdata1" {
  name                 = "${var.prefix}VM-DataDisk-1"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 64
}

resource "azurerm_virtual_machine_data_disk_attachment" "vmdata" {
  managed_disk_id    = azurerm_managed_disk.vmdata1.id
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  lun                = "10"
  caching            = "ReadWrite"
}

# Create and mount a backup disk to the VM
resource "azurerm_managed_disk" "vmbackup1" {
  name                 = "${var.prefix}VM-BackupDisk-1"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 64
}

resource "azurerm_virtual_machine_data_disk_attachment" "vmbackup" {
  managed_disk_id    = azurerm_managed_disk.vmbackup1.id
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  lun                = "11"
  caching            = "ReadWrite"
}

# Configure backup policy
resource "azurerm_recovery_services_vault" "vault" {
  name                = "${var.prefix}BackupVault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  soft_delete_enabled = false
}

resource "azurerm_backup_policy_vm" "vm" {
  name                = "${var.prefix}BackupVM"
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 7
  }
}

resource "azurerm_backup_protected_vm" "protectedvm" {
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  source_vm_id        = azurerm_linux_virtual_machine.vm.id
  backup_policy_id    = azurerm_backup_policy_vm.vm.id
}

# Output IP address
data "azurerm_public_ip" "ip" {
  name                = azurerm_public_ip.publicip.name
  resource_group_name = azurerm_linux_virtual_machine.vm.resource_group_name
  depends_on          = [azurerm_linux_virtual_machine.vm]
}

output "public_ip_address" {
  value = data.azurerm_public_ip.ip.ip_address
}
