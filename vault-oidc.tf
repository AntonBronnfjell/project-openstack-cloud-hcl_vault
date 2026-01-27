# ============================================================================
# Vault Service - Azure AD OIDC Authentication Configuration
# ============================================================================

# Configure Vault OIDC authentication after Vault is initialized and unsealed
resource "null_resource" "vault_oidc_config" {
  count = var.enable_azure_ad_oidc ? var.instance_count : 0

  depends_on = [
    null_resource.vault_docker_deploy,
    null_resource.vault_init
  ]

  triggers = {
    instance_ip           = openstack_compute_instance_v2.vault[count.index].network[0].fixed_ip_v4
    azure_ad_client_id    = var.azure_ad_client_id
    azure_ad_tenant_id    = var.azure_ad_tenant_id
    vault_oidc_role_name  = var.vault_oidc_default_role
    docker_compose_hash    = filemd5("${path.module}/docker/docker-compose.yml")
  }

  connection {
    type        = "ssh"
    host        = openstack_compute_instance_v2.vault[count.index].network[0].fixed_ip_v4
    user        = var.deploy_user
    private_key = var.ssh_private_key_path != "" ? file(var.ssh_private_key_path) : null
    timeout     = "10m"
  }

  # Copy OIDC configuration script
  provisioner "file" {
    source      = "${path.module}/scripts/configure-vault-oidc.sh"
    destination = "/tmp/configure-vault-oidc.sh"
  }

  # Execute OIDC configuration
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod +x /tmp/configure-vault-oidc.sh",
      
      # Set environment variables for the script
      "export VAULT_ADDR=https://localhost:${var.vault_port}",
      "export VAULT_SKIP_VERIFY=true",
      "export OIDC_CLIENT_ID='${var.azure_ad_client_id}'",
      "export OIDC_CLIENT_SECRET='${var.azure_ad_client_secret}'",
      "export OIDC_DISCOVERY_URL='https://login.microsoftonline.com/${var.azure_ad_tenant_id}/v2.0'",
      "export OIDC_ROLE_NAME='${var.vault_oidc_default_role}'",
      
      # Use bound audiences if specified, otherwise use client ID
      "export OIDC_BOUND_AUDIENCES='${length(var.vault_oidc_bound_audiences) > 0 ? join(",", var.vault_oidc_bound_audiences) : var.azure_ad_client_id}'",
      
      # Run the configuration script
      "/tmp/configure-vault-oidc.sh",
      
      # Cleanup
      "rm -f /tmp/configure-vault-oidc.sh",
      
      "echo 'OIDC configuration completed on instance ${count.index + 1}'"
    ]
  }
}
