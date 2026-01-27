# ============================================================================
# Vault Service - Initialization and Unsealing
# ============================================================================

# Initialize Vault (only on first instance)
# Vault must be initialized before it can be unsealed and used
resource "null_resource" "vault_init" {
  count = 1  # Only initialize once, on the first instance

  depends_on = [null_resource.vault_docker_deploy]

  triggers = {
    instance_id = openstack_compute_instance_v2.vault[0].id
    instance_ip = openstack_compute_instance_v2.vault[0].network[0].fixed_ip_v4
  }

  connection {
    type        = "ssh"
    host        = openstack_compute_instance_v2.vault[0].network[0].fixed_ip_v4
    user        = var.deploy_user
    private_key = var.ssh_private_key_path != "" ? file(var.ssh_private_key_path) : null
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo 'Initializing Vault...'",
      
      # Check if Vault is already initialized
      "if vault status 2>/dev/null | grep -q 'Initialized.*true'; then",
      "  echo 'Vault is already initialized'",
      "  exit 0",
      "fi",
      
      # Initialize Vault with 5 key shares and threshold of 3
      # This creates unseal keys that must be stored securely
      "echo 'Running Vault initialization...'",
      "vault operator init -key-shares=5 -key-threshold=3 -format=json > /tmp/vault-init.json 2>&1 || {",
      "  echo 'Vault initialization failed or already initialized'",
      "  cat /tmp/vault-init.json",
      "  exit 0  # Don't fail if already initialized",
      "}",
      
      # Display initialization info (without showing keys)
      "echo 'Vault initialized successfully'",
      "echo 'Unseal keys and root token saved to /tmp/vault-init.json'",
      "echo 'WARNING: Store these keys securely! They are required to unseal Vault.'",
      "",
      # Extract and display root token (first 8 chars only for security)
      "ROOT_TOKEN=$(jq -r '.root_token' /tmp/vault-init.json 2>/dev/null || echo '')",
      "if [ -n \"$$ROOT_TOKEN\" ]; then",
      "  TOKEN_PREFIX=$(echo \"$$ROOT_TOKEN\" | cut -c1-8)",
      "  echo \"Root token (first 8 chars): $$TOKEN_PREFIX...\"",
      "fi",
      
      # Note: Unsealing should be done manually or via auto-unseal
      # For production, consider using Azure Key Vault or other KMS for auto-unseal
      "echo ''",
      "echo 'Next steps:'",
      "echo '1. Retrieve unseal keys from /tmp/vault-init.json'",
      "echo '2. Unseal Vault using: vault operator unseal <key>'",
      "echo '3. Store keys securely (consider Azure Key Vault for auto-unseal)'"
    ]
  }
}

# Optional: Auto-unseal configuration (if using Azure Key Vault)
# Uncomment and configure if you want to use Azure Key Vault for auto-unseal
# resource "null_resource" "vault_auto_unseal" {
#   count = var.enable_azure_key_vault_unseal ? 1 : 0
#   
#   depends_on = [null_resource.vault_init]
#   
#   connection {
#     type        = "ssh"
#     host        = openstack_compute_instance_v2.vault[0].network[0].fixed_ip_v4
#     user        = var.deploy_user
#     private_key = var.ssh_private_key_path != "" ? file(var.ssh_private_key_path) : null
#   }
#   
#   provisioner "remote-exec" {
#     script = "${path.module}/scripts/configure-auto-unseal.sh"
#   }
# }
