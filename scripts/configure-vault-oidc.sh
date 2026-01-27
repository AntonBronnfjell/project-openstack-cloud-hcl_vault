#!/bin/bash
set -e

# Configure Vault OIDC authentication with Azure AD
# This script is called by Terraform after Vault is initialized and unsealed

echo "=========================================="
echo "Configuring Vault OIDC with Azure AD"
echo "=========================================="

# Set Vault address if not already set
export VAULT_ADDR="${VAULT_ADDR:-https://localhost:8200}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-true}"

# Wait for Vault to be unsealed and ready
echo "Waiting for Vault to be ready..."
MAX_RETRIES=60
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if vault status > /dev/null 2>&1; then
    echo "Vault is ready"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "Waiting for Vault... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "ERROR: Vault did not become ready within timeout period"
  exit 1
fi

# Check if Vault is sealed
if vault status | grep -q "Sealed.*true"; then
  echo "ERROR: Vault is sealed. Please unseal Vault before configuring OIDC."
  exit 1
fi

# Check if OIDC auth method is already enabled
if vault auth list | grep -q "^oidc/"; then
  echo "OIDC auth method already enabled"
else
  echo "Enabling OIDC auth method..."
  vault auth enable oidc
fi

# Configure OIDC with Azure AD
echo "Configuring OIDC with Azure AD..."
vault write auth/oidc/config \
  oidc_client_id="${OIDC_CLIENT_ID}" \
  oidc_client_secret="${OIDC_CLIENT_SECRET}" \
  oidc_discovery_url="${OIDC_DISCOVERY_URL}" \
  default_role="${OIDC_ROLE_NAME}"

# Determine bound audiences (use client ID if not specified)
BOUND_AUDIENCES="${OIDC_CLIENT_ID}"
if [ -n "${OIDC_BOUND_AUDIENCES}" ]; then
  BOUND_AUDIENCES="${OIDC_BOUND_AUDIENCES}"
fi

# Create default OIDC role
echo "Creating OIDC role: ${OIDC_ROLE_NAME}..."
vault write auth/oidc/role/${OIDC_ROLE_NAME} \
  user_claim="email" \
  groups_claim="groups" \
  bound_audiences="${BOUND_AUDIENCES}" \
  allowed_redirect_uris="https://chisel.graphicsforge.net/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="https://chisel.graphicsforge.net/oidc/callback" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  token_policies="default"

echo ""
echo "=========================================="
echo "Azure AD OIDC configuration complete!"
echo "=========================================="
echo "OIDC role: ${OIDC_ROLE_NAME}"
echo "Discovery URL: ${OIDC_DISCOVERY_URL}"
echo ""
echo "Users can now log in to Vault using Azure AD credentials."
echo "Access Vault UI at: https://chisel.graphicsforge.net"
