# ============================================================================
# Vault Service - Compute Instance Definitions (HA)
# ============================================================================

# Cloud-init script for k3s worker node (Vault will run on Kubernetes)
locals {
  cloud_init_script = <<-EOF
    #cloud-config
    # Vault Instance Cloud-init Configuration
    # Instance will join k3s cluster as worker node

    users:
      - name: ${var.deploy_user}
        groups: sudo
        shell: /bin/bash
        sudo: ['ALL=(ALL) NOPASSWD:ALL']
        ssh_authorized_keys:
          - ${var.ssh_public_key != "" ? var.ssh_public_key : ""}

    package_update: true
    package_upgrade: true

    packages:
      - curl
      - wget
      - git
      - vim
      - net-tools

    write_files:
      - path: /etc/modules-load.d/k8s.conf
        content: |
          overlay
          br_netfilter
        owner: root:root
        permissions: '0644'

      - path: /etc/sysctl.d/k8s.conf
        content: |
          net.bridge.bridge-nf-call-ip6tables = 1
          net.bridge.bridge-nf-call-iptables = 1
          net.ipv4.ip_forward = 1
        owner: root:root
        permissions: '0644'

    runcmd:
      # Load kernel modules
      - modprobe overlay
      - modprobe br_netfilter
      
      # Apply sysctl settings
      - sysctl --system
      
      # Note: k3s worker installation will be handled by the k3s cluster
      # This instance will be joined to the cluster via the master node
      # Vault will be deployed via Helm on the Kubernetes cluster
      
      # Create deployment user
      - usermod -aG docker ${var.deploy_user} || true
      
      # Log completion
      - echo "Vault instance (k3s worker) initialization complete" > /var/log/vault-init.log

    final_message: "Vault instance is ready to join k3s cluster"
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
    uuid = local.vault_network_id != "" ? local.vault_network_id : ""
    name = local.vault_network_id == "" ? (var.network_name != "" ? var.network_name : "k3s-network") : ""
  }

  security_groups = [
    openstack_networking_secgroup_v2.vault.name
  ]

  user_data = base64encode(templatefile("${path.module}/templates/vault-worker-cloud-init.yaml", {
    deploy_user = var.deploy_user
    ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : (fileexists("${pathexpand("~")}/.ssh/id_rsa.pub") ? file("${pathexpand("~")}/.ssh/id_rsa.pub") : "")
    k3s_token = var.k3s_token != "" ? var.k3s_token : ""
    k3s_master_ip = var.k3s_master_ip != "" ? var.k3s_master_ip : ""
  }))

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
