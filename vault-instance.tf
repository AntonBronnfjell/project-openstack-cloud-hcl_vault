# ============================================================================
# Vault Service - Compute Instance Definitions (HA)
# ============================================================================

# Cloud-init script for Docker installation and Vault setup
locals {
  cloud_init_script = <<-EOF
    #!/bin/bash
    set -e
    
    # Update system
    apt-get update
    apt-get install -y curl wget git
    
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create Vault directories
    mkdir -p ${var.vault_data_path}
    mkdir -p ${var.vault_config_path}/certs
    
    # Set permissions
    chmod 755 ${var.vault_data_path}
    chmod 755 ${var.vault_config_path}
    
    # Create systemd service for Vault (optional, for auto-start)
    # Vault will be managed via Docker Compose instead
    
    # Log completion
    echo "Vault instance initialization complete" > /var/log/vault-init.log
  EOF
}

# Create multiple Vault instances for high availability
resource "openstack_compute_instance_v2" "vault" {
  provider    = openstack
  count       = var.instance_count
  name        = "vault-${count.index + 1}"
  flavor_name = var.instance_flavor
  image_name  = var.instance_image
  key_pair    = var.ssh_key_name != "" ? var.ssh_key_name : null

  network {
    uuid = data.openstack_networking_network_v2.vault_network.id
  }

  security_groups = [
    openstack_networking_secgroup_v2.vault.name
  ]

  user_data = base64encode(local.cloud_init_script)

  # Lifecycle management for zero-downtime deployments
  lifecycle {
    create_before_destroy = true
    ignore_changes       = [user_data]
  }

  metadata = {
    service     = "vault"
    instance_id = count.index + 1
    domain      = var.domain
    subdomain   = var.subdomain
  }
}

# Get floating IPs for instances (if needed for external access)
# Note: Floating IPs are optional - instances can be accessed via internal network
# Uncomment if external access is required:
# resource "openstack_networking_floatingip_v2" "vault" {
#   provider = openstack
#   count    = var.instance_count
#   pool     = "public"
# }
# 
# resource "openstack_compute_floatingip_associate_v2" "vault" {
#   provider    = openstack
#   count       = var.instance_count
#   instance_id = openstack_compute_instance_v2.vault[count.index].id
#   floating_ip = openstack_networking_floatingip_v2.vault[count.index].address
# }
