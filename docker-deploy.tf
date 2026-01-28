# ============================================================================
# Vault Service - Docker Deployment
# ============================================================================
# Handles Docker Compose deployment with proper SSH timeout handling
# to prevent Terraform from getting stuck during deployment

# Wait for SSH to become available (with timeout to prevent hanging)
# Only created if SSH key is configured
# This resource has a short timeout and will fail fast if SSH isn't available
resource "null_resource" "vault_wait_for_ssh" {
  count = var.ssh_private_key_path != "" ? var.instance_count : 0

  depends_on = [openstack_compute_instance_v2.vault]

  triggers = {
    instance_id = openstack_compute_instance_v2.vault[count.index].id
    instance_ip = openstack_compute_instance_v2.vault[count.index].network[0].fixed_ip_v4
  }

  connection {
    type        = "ssh"
    host        = openstack_compute_instance_v2.vault[count.index].network[0].fixed_ip_v4
    user        = var.deploy_user
    private_key = file(var.ssh_private_key_path)
    timeout     = "1m"  # Short timeout - fail fast if SSH isn't ready
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'SSH connection successful'",
      "uptime"
    ]
  }
  
  # Add lifecycle to allow this to be recreated if it fails
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [triggers]
  }
}

# Deploy Docker Compose stack
# This will proceed even if SSH wait fails
resource "null_resource" "vault_docker_deploy" {
  count = var.instance_count

  # Wait for instance to be created
  # Note: We don't strictly depend on SSH wait to prevent blocking
  # Docker deployment will retry SSH connection itself
  depends_on = [
    openstack_compute_instance_v2.vault
  ]

  triggers = {
    instance_id        = openstack_compute_instance_v2.vault[count.index].id
    instance_ip        = openstack_compute_instance_v2.vault[count.index].network[0].fixed_ip_v4
    docker_compose_hash = filemd5("${path.module}/docker/docker-compose.yml")
    stack_env_hash     = sha256(join("\n", [
      "PORT=${var.vault_port}",
      "VAULT_ADDR=${var.vault_addr}",
      "VAULT_API_ADDR=${var.vault_api_addr}"
    ]))
  }

  connection {
    type        = "ssh"
    host        = openstack_compute_instance_v2.vault[count.index].network[0].fixed_ip_v4
    user        = var.deploy_user
    private_key = var.ssh_private_key_path != "" ? file(var.ssh_private_key_path) : null
    timeout     = "3m"  # Reduced timeout to fail faster
    agent       = false
  }

  # Deploy Docker Compose files
  provisioner "file" {
    source      = "${path.module}/docker/docker-compose.yml"
    destination = "/opt/vault/docker-compose.yml"
  }

  # Generate and deploy stack.env
  provisioner "file" {
    content = <<-EOF
PORT=${var.vault_port}
VAULT_ADDR=${var.vault_addr}
VAULT_API_ADDR=${var.vault_api_addr}
EOF
    destination = "/opt/vault/stack.env"
  }

  # Deploy and start Docker containers
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "cd /opt/vault",
      "echo 'Deploying Vault Docker containers...'",
      
      # Ensure Docker is running (cloud-init should have installed it)
      "systemctl start docker 2>/dev/null || true",
      "systemctl enable docker 2>/dev/null || true",
      "sleep 5",  # Give Docker time to start
      
      # Stop existing containers if any
      "docker-compose down 2>/dev/null || true",
      
      # Pull latest images
      "docker-compose pull || echo 'Warning: docker-compose pull failed, continuing...'",
      
      # Start containers in detached mode
      "docker-compose up -d",
      
      # Wait for containers to be healthy
      "echo 'Waiting for Vault containers to start...'",
      "sleep 10",
      
      # Check container status
      "docker-compose ps",
      
      "echo 'Vault Docker deployment completed on instance ${count.index + 1}'"
    ]
  }
  
  # Allow this resource to be recreated if deployment fails
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [triggers]
  }
}
