//We are creating a resource group to add all the azure there to group and manage them easily
resource "azurerm_resource_group" "rg" {
    location = "eastus"
    name = "tektutor-rg"
}

//We are creating a virtual network
resource "azurerm_virtual_network" "my_virtual_network" {
    name = "my-virtual-net"
    address_space = ["10.0.0.0/16"]
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    depends_on = [
        azurerm_resource_group.rg
    ]
}

//We are creating a subnet within the virtual network
resource "azurerm_subnet" "my_subnet" {
  name = "mySubnet"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.my_virtual_network.name
  address_prefixes = ["10.0.1.0/24"]
  depends_on = [
    azurerm_virtual_network.my_virtual_network
  ]
}

//We are creating public ip address for the 3 VMs we are about to create
resource "azurerm_public_ip" "my_public_ip" {
  count = 3
  name = "myPublicIP${count.index}"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method = "Dynamic"    
  depends_on = [
    azurerm_resource_group.rg
  ]
}

//Firewall - we can open up the required ports on the Virtual Machines 
resource "azurerm_network_security_group" "my-nsg" {
  count = 3
  name = "myNetworkSecurityGroup${count.index}"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name = "SSH"    
    priority = "1001"
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "22"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name = "OpenHttpPort"    
    priority = "100"
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "80"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name = "OpenICMPPort"    
    priority = "200"
    direction = "Inbound"
    access = "Allow"
    protocol = "ICMP"
    source_port_range = "*"
    destination_port_range = "*"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }

  depends_on = [
    azurerm_resource_group.rg
  ]
}

//Creating network cards to be assigned with the virtual machines that will be created below
resource "azurerm_network_interface" "my_nic" {
  count = 3
  name = "myNIC${count.index}"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name = "my_nic_configuration${count.index}"
    subnet_id = azurerm_subnet.my_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.my_public_ip[count.index].id
  }  
  depends_on = [
    azurerm_resource_group.rg,
    azurerm_public_ip.my_public_ip
  ]
}

//Integrating the network firewall settings with the network card
resource "azurerm_network_interface_security_group_association"  "nic_ngs_connector" {
  count = 3
  network_interface_id = azurerm_network_interface.my_nic[count.index].id
  network_security_group_id = azurerm_network_security_group.my-nsg[count.index].id
  depends_on = [
    azurerm_resource_group.rg
  ]
}

//Creating key pair for login authentication using key pairs
resource "tls_private_key" "my_ssh_key" {
    algorithm = "RSA"
    rsa_bits = 4096
  depends_on = [
    azurerm_resource_group.rg
  ]
}

//Creating 3 Ubuntu azure virtual machines
resource "azurerm_linux_virtual_machine" "my_ubuntu_vm" {
  count = 3
  name = "myUbuntuVM${count.index}"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.my_nic[count.index].id]
  size = "Standard_DS1_v2"

  os_disk {
    name = "myHardDisk${count.index}"
    caching = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "UbuntuServer"
    sku = "18.04-LTS"
    version = "latest"
  }

  computer_name = "myvm${count.index}"
  admin_username = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username = "azureuser"
    public_key = tls_private_key.my_ssh_key.public_key_openssh
  }
  
  depends_on = [
    azurerm_resource_group.rg, 
    azurerm_network_interface.my_nic,
    azurerm_network_security_group.my-nsg,
    azurerm_network_interface_security_group_association.nic_ngs_connector
  ]
}

resource "null_resource" "delete_ip_files_and_pem_file" {
  provisioner "local-exec" {
    command = "rm -f key.pem ip*.txt" 
  }
  depends_on = [
    azurerm_resource_group.rg
  ]
}
   
   
//Storing the private key we generated. Required for ansible playbook execution
resource "local_file" "private-key" {
  content  = tls_private_key.my_ssh_key.private_key_openssh
  filename = "./key.pem"
  
  provisioner "local-exec" {
    command = "chmod 400 ./key.pem" 
  }

  depends_on = [ 
     azurerm_linux_virtual_machine.my_ubuntu_vm[0],
     azurerm_linux_virtual_machine.my_ubuntu_vm[1],
     azurerm_linux_virtual_machine.my_ubuntu_vm[2]
  ] 
}

//Storing the ip addresses of the azure virtual machine we provisioned using Terraform
//Required for Ansible playbook execution - used in inventory
resource "local_file" "ip" {
  count = 3
  content  = azurerm_linux_virtual_machine.my_ubuntu_vm[count.index].public_ip_address 
  filename = "./ip${count.index}.txt"
  
  provisioner "local-exec" {
    command = "ansible-playbook -u azureuser -i ./ip${count.index}.txt --private-key ./key.pem install-nginx-playbook.yml" 
  }

  depends_on = [ 
     azurerm_linux_virtual_machine.my_ubuntu_vm[0],
     azurerm_linux_virtual_machine.my_ubuntu_vm[1], 
     azurerm_linux_virtual_machine.my_ubuntu_vm[2] 
  ] 
}
