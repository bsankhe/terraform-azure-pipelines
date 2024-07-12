resource "random_pet" "rg_name" {
   prefix = var.resource_group_name_prefix
}

resource "azurerm_resource_group" "rg" {
    location = var.resource_group_location
    name = random_pet.rg_name.id
    depends_on = [
        random_pet.rg_name
    ]
}

resource "azurerm_virtual_network" "my_virtual_network" {
    name = "my-virtual-net"
    address_space = ["10.0.0.0/16"]
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    depends_on = [
        azurerm_resource_group.rg
    ]
}

resource "azurerm_subnet" "my_subnet" {
  name = "mySubnet"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.my_virtual_network.name
  address_prefixes = ["10.0.1.0/24"]
  depends_on = [
    azurerm_virtual_network.my_virtual_network
  ]
}

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
    protocol = "Icmp"
    source_port_range = "*"
    destination_port_range = "*"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }

  depends_on = [
    azurerm_resource_group.rg
  ]
}

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

resource "azurerm_network_interface_security_group_association"  "nic_ngs_connector" {
  count = 3
  network_interface_id = azurerm_network_interface.my_nic[count.index].id
  network_security_group_id = azurerm_network_security_group.my-nsg[count.index].id
  depends_on = [
    azurerm_resource_group.rg
  ]
}

resource "tls_private_key" "my_ssh_key" {
    algorithm = "RSA"
    rsa_bits = 4096
  depends_on = [
    azurerm_resource_group.rg
  ]
}

resource "azurerm_linux_virtual_machine" "my_ubuntu_vm" {
  count = 3
  name = "myUbuntuVM${count.index}"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.my_nic[count.index].id]
  size = "Standard_F2"

  os_disk {
    name = "myHardDisk${count.index}"
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "0001-com-ubuntu-server-jammy"
    sku = "22_04-lts"
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

resource "local_file" "key_pem" {
    filename = "./key.pem"
    content  = tls_private_key.my_ssh_key.private_key_openssh
    file_permission = "0400"
   
    provisioner "local-exec" {
      command = "cat ./key.pem" 
    }
}

resource "local_file" "store_vm_ips_to_file_for_ansible_provisioning" {
  count = 3
  content  = azurerm_linux_virtual_machine.my_ubuntu_vm[count.index].public_ip_address 
  filename = "./ip${count.index}.txt"

  provisioner "local-exec" {
     command = "cat ./ip${count.index}.txt" 
  }
  
  depends_on = [ 
     azurerm_linux_virtual_machine.my_ubuntu_vm[0],
     azurerm_linux_virtual_machine.my_ubuntu_vm[1], 
     azurerm_linux_virtual_machine.my_ubuntu_vm[2] 
  ] 
}

resource "time_sleep" "wait_45_seconds" {
   create_duration = "45s"  
   depends_on = [ 
     local_file.store_vm_ips_to_file_for_ansible_provisioning[0],
     local_file.store_vm_ips_to_file_for_ansible_provisioning[1],
     local_file.store_vm_ips_to_file_for_ansible_provisioning[2]
  ]   
}

//Storing the ip addresses of the azure virtual machine we provisioned using Terraform
//Required for Ansible playbook execution - used in inventory
resource "null_resource" "ip" {
  count = 3
  
  provisioner "local-exec" {
    command = "ansible-playbook -u azureuser -i ./ip${count.index}.txt --private-key ./key.pem install-nginx-playbook.yml -vvvv" 
  }

  depends_on = [ 
     local_file.store_vm_ips_to_file_for_ansible_provisioning[0],
     local_file.store_vm_ips_to_file_for_ansible_provisioning[1],
     local_file.store_vm_ips_to_file_for_ansible_provisioning[2],
     time_sleep.wait_45_seconds
  ] 
}
