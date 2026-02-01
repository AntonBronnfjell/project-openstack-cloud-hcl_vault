# ============================================================================
# Vault Service - Compute Instance Definitions (HA)
# ============================================================================
# Vault instances run Docker Compose for containerized deployment

# Create multiple Vault instances for high availability
resource "openstack_compute_instance_v2" "vault" {
  provider    = openstack
  count       = var.instance_count
  name        = "vault-${count.index + 1}"
  flavor_name = var.instance_flavor
  image_name  = var.instance_image
  key_pair    = var.ssh_key_name != "" ? var.ssh_key_name : null

  network {
    uuid = local.vault_network_id != "" ? local.vault_network_id : null
    name = local.vault_network_id == "" ? (var.network_name != "" ? var.network_name : "vault-network") : null
  }

  security_groups = [
    openstack_networking_secgroup_v2.vault.id
  ]

  user_data = base64encode(templatefile("${path.module}/templates/vault-docker-cloud-init.yaml", {
    deploy_user    = var.deploy_user
    ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : (fileexists("${pathexpand("~")}/.ssh/id_rsa.pub") ? file("${pathexpand("~")}/.ssh/id_rsa.pub") : "")
  }))

  # Lifecycle management for zero-downtime deployments
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [user_data, security_groups]  # Temporarily ignore security_groups to avoid conflicts
    # Prevent accidental destruction - remove this if you need to destroy instances
    # prevent_destroy = true
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
