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

# Data source for network
# Use network_id if provided, otherwise lookup by name
data "openstack_networking_network_v2" "vault_network" {
  provider   = openstack
  network_id = var.network_id != "" ? var.network_id : null
  name       = var.network_id == "" && var.network_name != "" ? var.network_name : null
}

# Data source for subnet
data "openstack_networking_subnet_v2" "vault_subnet" {
  provider  = openstack
  network_id = data.openstack_networking_network_v2.vault_network.id
  ip_version = 4
}
