# ============================================================================
# Vault Service - Network and Security Group Configuration
# ============================================================================

# Security group for Vault instances
resource "openstack_networking_secgroup_v2" "vault" {
  provider    = openstack
  name        = var.security_group_name
  description = "Security group for Vault service instances"
}

# Allow SSH access (for deployment and management)
resource "openstack_networking_secgroup_rule_v2" "vault_ssh" {
  provider          = openstack
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.vault.id
  description       = "Allow SSH access for deployment"
}

# Allow Vault HTTPS port (8200)
resource "openstack_networking_secgroup_rule_v2" "vault_https" {
  provider          = openstack
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = var.vault_port
  port_range_max    = var.vault_port
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.vault.id
  description       = "Allow Vault HTTPS access"
}

# Allow Vault cluster communication (for HA)
resource "openstack_networking_secgroup_rule_v2" "vault_cluster" {
  provider          = openstack
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8201
  port_range_max    = 8201
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.vault.id
  description       = "Allow Vault cluster communication for HA"
}

# Create network if it doesn't exist
resource "openstack_networking_network_v2" "vault_network" {
  count         = var.network_id == "" && var.network_name != "" ? 1 : 0
  provider      = openstack
  name          = var.network_name
  admin_state_up = true
}

# Create subnet for the network if it was created
resource "openstack_networking_subnet_v2" "vault_subnet" {
  count      = var.network_id == "" && var.network_name != "" ? 1 : 0
  provider   = openstack
  name       = "${var.network_name}-subnet"
  network_id = openstack_networking_network_v2.vault_network[0].id
  cidr       = "10.0.0.0/24"
  ip_version = 4
  enable_dhcp = true
  
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}

# Data source for network (use existing network by ID, or lookup by name, or use created network)
locals {
  network_id_to_use = var.network_id != "" ? var.network_id : (
    var.network_name != "" && length(openstack_networking_network_v2.vault_network) > 0 ? openstack_networking_network_v2.vault_network[0].id : null
  )
}

data "openstack_networking_network_v2" "vault_network" {
  provider   = openstack
  network_id = local.network_id_to_use != null ? local.network_id_to_use : null
  name       = local.network_id_to_use == null && var.network_name != "" ? var.network_name : null
}

# Data source for subnet (use created subnet or lookup existing one)
locals {
  subnet_id_to_use = var.network_id == "" && var.network_name != "" && length(openstack_networking_subnet_v2.vault_subnet) > 0 ? openstack_networking_subnet_v2.vault_subnet[0].id : null
}

data "openstack_networking_subnet_v2" "vault_subnet" {
  provider   = openstack
  subnet_id  = local.subnet_id_to_use
  network_id = local.subnet_id_to_use == null ? data.openstack_networking_network_v2.vault_network.id : null
  ip_version  = 4
}
