#!/bin/bash
# Vault Deployment Script
# This script is used by Terraform to deploy Vault on OpenStack instances

set -e

VAULT_CONFIG_PATH="${VAULT_CONFIG_PATH:-/opt/vault/config}"
VAULT_DATA_PATH="${VAULT_DATA_PATH:-/opt/vault/data}"

echo "Deploying Vault Docker stack..."

# Ensure directories exist
mkdir -p "${VAULT_CONFIG_PATH}/certs"
mkdir -p "${VAULT_DATA_PATH}"

# Copy Docker Compose and environment files
cp /tmp/docker-compose.yml "${VAULT_CONFIG_PATH}/docker-compose.yml"
cp /tmp/stack.env "${VAULT_CONFIG_PATH}/stack.env"

# Copy TLS certificates if provided
if [ -f /tmp/vault-cert.pem ] && [ -s /tmp/vault-cert.pem ]; then
  cp /tmp/vault-cert.pem "${VAULT_CONFIG_PATH}/certs/vault-cert.pem"
  chmod 644 "${VAULT_CONFIG_PATH}/certs/vault-cert.pem"
fi

if [ -f /tmp/vault-key.pem ] && [ -s /tmp/vault-key.pem ]; then
  cp /tmp/vault-key.pem "${VAULT_CONFIG_PATH}/certs/vault-key.pem"
  chmod 600 "${VAULT_CONFIG_PATH}/certs/vault-key.pem"
fi

# Start Docker Compose stack
cd "${VAULT_CONFIG_PATH}"
docker-compose -f docker-compose.yml --env-file stack.env up -d

# Wait for Vault to be ready
echo "Waiting for Vault to start..."
sleep 10

# Health check
for i in {1..30}; do
  if curl -k -s https://localhost:8200/v1/sys/health > /dev/null 2>&1; then
    echo "Vault is healthy"
    exit 0
  fi
  echo "Waiting for Vault health check... ($i/30)"
  sleep 2
done

echo "Vault deployment complete"
