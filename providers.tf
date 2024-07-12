terraform {
  required_providers {
    azurerm = {
        source = "hashicorp/azurerm"
        version = "3.112.0"
    }
    random = {
        source = "hashicorp/random"
        version = "3.6.2"
    }

    tls = {
        source = "hashicorp/tls"
        version = "4.0.5"
    }
 }
}

provider "azurerm" {
  features {}
}
