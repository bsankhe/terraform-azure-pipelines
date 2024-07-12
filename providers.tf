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
  subscription_id = "82dfc44c-fa64-4e95-a9a9-2777d9258514"
  tenant_id = "138cb8e2-0b13-46b8-8361-7c09b21772bb"
}
