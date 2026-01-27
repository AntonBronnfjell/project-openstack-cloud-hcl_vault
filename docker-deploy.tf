# ============================================================================
# Vault Service - Docker Container Deployment
# ============================================================================

# Get instance IPs
locals {
  instance_ips = [
    for instance in openstack_compute_instance_v2.vault : 
    instance.network[0].fixed_ip_v4
  ]
  
  # SSH connection configuration
  ssh_connections = {
    for idx, instance in openstack_compute_instance_v2.vault :
    idx => {
      host        = instance.network[0].fixed_ip_v4
      user        = var.deploy_user
      private_key = var.ssh_private_key_path != "" ? file(var.ssh_private_key_path) : null
    }
  }
}

# Deploy Docker Compose stack to each instance
resource "null_resource" "vault_docker_deploy" {
  count = var.instance_count

  # Trigger on instance creation or Docker Compose file changes
  triggers = {
    instance_id     = openstack_compute_instance_v2.vault[count.index].id
    docker_compose  = filemd5("${path.module}/docker/docker-compose.yml")
    stack_env       = fileexists("${path.module}/docker/stack.env") ? filemd5("${path.module}/docker/stack.env") : "default"
    instance_ip     = openstack_compute_instance_v2.vault[count.index].network[0].fixed_ip_v4
  }

  # Wait for instance to be ready
  # Only wait for SSH if SSH key is configured, otherwise just wait for instance creation
  depends_on = concat(
    [openstack_compute_instance_v2.vault],
    var.ssh_private_key_path != "" ? [null_resource.vault_wait_for_ssh[count.index]] : []
  )

  connection {
    type        = "ssh"
    host        = openstack_compute_instance_v2.vault[count.index].network[0].fixed_ip_v4
    user        = var.deploy_user
    private_key = var.ssh_private_key_path != "" ? file(var.ssh_private_key_path) : null
    timeout     = "5m"
  }

  # Copy Docker Compose file
  provisioner "file" {
    source      = "${path.module}/docker/docker-compose.yml"
    destination = "/tmp/docker-compose.yml"
  }

  # Copy environment file (create from template if not exists)
  provisioner "file" {
    content = <<-ENV
PORT=${var.vault_port}
VAULT_ADDR=${var.vault_addr}
VAULT_API_ADDR=${var.vault_api_addr}
VAULT_VERSION=${var.vault_version}
ENV
    destination = "/tmp/stack.env"
  }

  # Copy TLS certificates if provided
  provisioner "file" {
    source      = var.tls_cert_path != "" ? var.tls_cert_path : "/dev/null"
    destination = "/tmp/vault-cert.pem"
    when        = create
    on_failure  = continue
  }

  provisioner "file" {
    source      = var.tls_key_path != "" ? var.tls_key_path : "/dev/null"
    destination = "/tmp/vault-key.pem"
    when        = create
    on_failure  = continue
  }

  # Deploy Vault stack
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo 'Deploying Vault Docker stack on instance ${count.index + 1}...'",
      
      # Move files to deployment directory
      "sudo mkdir -p ${var.vault_config_path}/certs",
      "sudo cp /tmp/docker-compose.yml ${var.vault_config_path}/docker-compose.yml",
      "sudo cp /tmp/stack.env ${var.vault_config_path}/stack.env",
      
      # Copy TLS certificates if provided
      "if [ -f /tmp/vault-cert.pem ] && [ -s /tmp/vault-cert.pem ]; then",
      "  sudo cp /tmp/vault-cert.pem ${var.vault_config_path}/certs/vault-cert.pem",
      "  sudo chmod 644 ${var.vault_config_path}/certs/vault-cert.pem",
      "fi",
      "if [ -f /tmp/vault-key.pem ] && [ -s /tmp/vault-key.pem ]; then",
      "  sudo cp /tmp/vault-key.pem ${var.vault_config_path}/certs/vault-key.pem",
      "  sudo chmod 600 ${var.vault_config_path}/certs/vault-key.pem",
      "fi",
      
      # Create Vault configuration file
      "sudo tee ${var.vault_config_path}/vault.json > /dev/null <<'VAULT_CONFIG'",
      <<-VAULT_CONFIG
{
  "listener": [
    {
      "tcp": {
        "address": "0.0.0.0:8200",
        "tls_disable": 0,
        "tls_cert_file": "/vault/config/certs/vault-cert.pem",
        "tls_key_file": "/vault/config/certs/vault-key.pem"
      }
    }
  ],
  "storage": {
    "file": {
      "path": "/vault/data"
    }
  },
  "default_lease_ttl": "168h",
  "max_lease_ttl": "720h",
  "ui": true
}
VAULT_CONFIG
      ,
      
      # Start Docker Compose stack
      "cd ${var.vault_config_path}",
      "sudo docker-compose -f docker-compose.yml --env-file stack.env up -d",
      
      # Wait for Vault to be ready
      "echo 'Waiting for Vault to start...'",
      "sleep 10",
      
      # Health check
      "for i in {1..30}; do",
      "  if curl -k -s https://localhost:${var.vault_port}/v1/sys/health > /dev/null 2>&1; then",
      "    echo 'Vault is healthy'",
      "    break",
      "  fi",
      "  echo 'Waiting for Vault health check... ($i/30)'",
      "  sleep 2",
      "done",
      
      "echo 'Vault deployment complete on instance ${count.index + 1}'"
    ]
  }
}

# Wait for SSH to be available on instances (only if SSH key is configured)
resource "null_resource" "vault_wait_for_ssh" {
  count = var.instance_count * (var.ssh_private_key_path != "" ? 1 : 0)

  triggers = {
    instance_id = openstack_compute_instance_v2.vault[count.index].id
  }

  connection {
    type        = "ssh"
    host        = openstack_compute_instance_v2.vault[count.index].network[0].fixed_ip_v4
    user        = var.deploy_user
    private_key = var.ssh_private_key_path != "" ? file(var.ssh_private_key_path) : null
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'SSH connection established'"
    ]
  }
}
