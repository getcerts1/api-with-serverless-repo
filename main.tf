terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }
  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "app-rg-1"
  location = var.location
}

# Hub VNet
resource "azurerm_virtual_network" "hub_vnet" {
  name                = "hub-vnete"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "Bastion_subnet" {
  name                 = "AzureBastionSubnet"
  address_prefixes     = ["10.0.0.0/24"]
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
}

resource "azurerm_subnet" "Firewall_subnet" {
  name                 = "AzureFirewallSubnet"
  address_prefixes     = ["10.0.1.0/26"]
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
}

# Public IPs
resource "azurerm_public_ip" "bastion_pip" {
  name                = "Bastion-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "bastion_host" {
  name                = "hub-bastion"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.Bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
  }
}

resource "azurerm_public_ip" "firewall_pip" {
  name                = "Firewall-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_firewall" "utilities_firewall" {
  name                = "utilities_firewall"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
}

# Spoke VNet 1 (App VNet)
resource "azurerm_virtual_network" "app_vnet" {
  name                = "app-vnet"
  address_space = ["10.1.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

}

resource "azurerm_subnet" "Web_tier_subnet" {
  name = "web-tier-subnet"
  address_prefixes = ["10.1.1.0/24"]
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.app_vnet.name
}

resource "azurerm_subnet" "ApplicationGatewaySubnet" {
    name           = "ApplicationGatewaySubnet"
    address_prefixes = ["10.1.0.0/24"]
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.app_vnet.name
  }

resource "azurerm_subnet" "Database_subnet" {
  name           = "database_subnet"
  address_prefixes = ["10.1.0.0/24"]
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.app_vnet.name
}


# Spoke VNet 2 (Storage VNet)
resource "azurerm_virtual_network" "storage_vnet" {
  name                = "storage_vnet"
  address_space       = ["10.2.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

}

resource azurerm_subnet "storage_subnet" {
    name           = "storage_subnet"
    address_prefixes = ["10.2.0.0/24"]
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.storage_vnet.name
}

resource "azurerm_storage_account" "storage_account" {
  name                     = "utilitiesappstorage"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_private_endpoint" "storage_private_endpoint" {
  name                = "storage-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id = azurerm_subnet.Web_tier_subnet.id


  private_service_connection {
    name                           = "storage-to-web-connection"
    private_connection_resource_id = azurerm_storage_account.storage_account.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}

resource "azurerm_private_dns_zone" "web_tier_storage_dns_zone" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "web_tier_storage_dns_link" {
  name                  = "web_tier_storage-dns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.web_tier_storage_dns_zone.name
  virtual_network_id    = lookup(azurerm_virtual_network.app_vnet, "id")
}