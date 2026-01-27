# Azure AD OIDC Authentication Setup for Vault

This guide covers the configuration of Azure AD OIDC authentication for HashiCorp Vault, allowing users to log in with their Azure AD credentials instead of managing tokens.

## Overview

Azure AD OIDC authentication enables:
- Single Sign-On (SSO) with Azure AD
- No need to manage Vault tokens manually
- Integration with Azure AD groups for policy assignment
- Secure authentication flow via OAuth 2.0 / OIDC

## Prerequisites

- Azure AD tenant access
- Vault deployed and accessible at `https://chisel.graphicsforge.net`
- Vault initialized and unsealed
- Network access to Azure AD endpoints (`login.microsoftonline.com`)

## Azure AD Application Registration

### Status: ✅ COMPLETED

The Azure AD application has been registered with the following configuration:

- **Application Name**: Vault OIDC Application
- **Client ID**: `your-client-id-here` (configured in Azure AD)
- **Tenant ID**: `your-tenant-id-here` (configured in Azure AD)
- **Redirect URIs**:
  - `https://chisel.graphicsforge.net/ui/vault/auth/oidc/oidc/callback` (Vault UI)
  - `https://chisel.graphicsforge.net/oidc/callback` (Alternative callback)
  - `http://localhost:8250/oidc/callback` (CLI access)

### Optional: Configure Group Claims

To enable Azure AD group mapping to Vault policies:

1. Navigate to Azure Portal → Azure Active Directory → App registrations
2. Select your Vault application
3. Go to "Token configuration"
4. Click "Add optional claim"
5. Select "groups"
6. Choose "Security groups" or "All groups"
7. Save changes

This enables the `groups` claim in JWT tokens, which can be used for Vault policy assignment.

## Configuration

### Environment Variables

Create `.env.azure` file (copy from `.env.azure.example`):

```bash
# Vault OIDC Application
AZURE_AD_TENANT_ID=your-tenant-id-here
AZURE_AD_CLIENT_ID=your-client-id-here
AZURE_AD_CLIENT_SECRET=your-client-secret-here
```

### Terraform Variables

The Vault module accepts Azure AD OIDC variables:

```hcl
module "vault_service" {
  # ... other configuration ...
  
  enable_azure_ad_oidc = true
  azure_ad_tenant_id   = var.azure_ad_tenant_id
  azure_ad_client_id   = var.azure_ad_client_id
  azure_ad_client_secret = var.azure_ad_client_secret
  vault_oidc_default_role = "azure-ad"
}
```

## Authentication Flow

1. **User Access**: User navigates to `https://chisel.graphicsforge.net`
2. **Redirect**: Vault redirects to Azure AD login page
3. **Authentication**: User authenticates with Azure AD credentials
4. **Token Exchange**: Azure AD issues signed JWT token
5. **Vault Verification**: Vault verifies JWT and exchanges for Vault token
6. **Access Granted**: User gains access with policies based on Azure AD claims

## User Login Process

### Via Vault UI

1. Navigate to `https://chisel.graphicsforge.net`
2. Click "Sign in with OIDC Provider" or select "oidc" auth method
3. You will be redirected to Azure AD login
4. Enter your Azure AD credentials
5. After successful authentication, you'll be redirected back to Vault
6. You now have a Vault token with appropriate policies

### Via CLI

```bash
# Set Vault address
export VAULT_ADDR=https://chisel.graphicsforge.net

# Login with OIDC
vault auth -method=oidc

# Follow the browser-based authentication flow
# The CLI will open your browser for Azure AD login
```

## Vault OIDC Role Configuration

The default OIDC role (`azure-ad`) is configured with:

- **User Claim**: `email` - Uses email from Azure AD token
- **Groups Claim**: `groups` - Uses Azure AD groups (if configured)
- **Bound Audiences**: Client ID (`8048ed14-c914-45ab-a707-fafce9290fd2`)
- **Token Policies**: `default` (can be customized)
- **Redirect URIs**: Configured for UI and CLI access

### Customizing Policies

To assign custom policies to Azure AD authenticated users:

```bash
# Create a custom policy
vault policy write my-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}
EOF

# Update OIDC role to use custom policy
vault write auth/oidc/role/azure-ad \
  token_policies="default,my-policy"
```

### Group-Based Policy Assignment

If Azure AD groups are configured:

1. Create Vault external groups:
```bash
vault write identity/group name="admins" type="external"
vault write identity/group name="developers" type="external"
```

2. Create group aliases linking Azure AD groups:
```bash
# Get Azure AD group Object ID from Azure Portal
AZURE_AD_GROUP_ID="your-azure-ad-group-object-id"

vault write identity/group-alias \
  name="${AZURE_AD_GROUP_ID}" \
  mount_accessor=$(vault auth list -format=json | jq -r '."oidc/".accessor') \
  canonical_id=$(vault read -field=id identity/group/name/admins)
```

3. Assign policies to groups:
```bash
vault write identity/group/id/<group-id> policies="admin-policy"
```

## Troubleshooting

### Vault OIDC Not Appearing

**Issue**: OIDC auth method not visible in Vault UI

**Solution**:
1. Verify Vault is unsealed: `vault status`
2. Check if OIDC is enabled: `vault auth list`
3. If not enabled, run the configuration script manually:
```bash
./scripts/configure-vault-oidc.sh
```

### Authentication Fails

**Issue**: Azure AD login fails or redirects incorrectly

**Solutions**:
1. Verify redirect URIs match exactly in Azure AD app registration
2. Check that the domain `chisel.graphicsforge.net` resolves correctly
3. Verify TLS certificates are valid
4. Check Vault logs: `docker logs vault`

### Token Policies Not Applied

**Issue**: User can authenticate but doesn't have expected permissions

**Solutions**:
1. Verify OIDC role configuration: `vault read auth/oidc/role/azure-ad`
2. Check token policies: `vault token lookup <token>`
3. Verify policies exist: `vault policy list`
4. Update role with correct policies: `vault write auth/oidc/role/azure-ad token_policies="policy1,policy2"`

### Groups Not Mapping

**Issue**: Azure AD groups not appearing in Vault token

**Solutions**:
1. Verify groups claim is configured in Azure AD app registration
2. Check token claims: Decode JWT token and verify `groups` claim exists
3. Verify group aliases are configured correctly
4. Check Vault identity groups: `vault list identity/group`

## Security Considerations

1. **Client Secret**: Store Azure AD client secret securely (environment variables, secret manager)
2. **Redirect URIs**: Ensure redirect URIs match exactly (including protocol and port)
3. **Token Policies**: Configure appropriate Vault policies for Azure AD authenticated users
4. **Group Mapping**: Use Azure AD groups for fine-grained access control
5. **Audit Logging**: Enable Vault audit logging to track authentication events

## Testing

### Verify OIDC Configuration

```bash
# Check OIDC auth method is enabled
vault auth list

# View OIDC configuration
vault read auth/oidc/config

# View OIDC role
vault read auth/oidc/role/azure-ad
```

### Test Authentication

1. Open browser: `https://chisel.graphicsforge.net`
2. Select "oidc" authentication method
3. Complete Azure AD login
4. Verify you receive a Vault token
5. Test token permissions: `vault token capabilities <token> secret/data/test`

## References

- [Vault OIDC Auth Method](https://developer.hashicorp.com/vault/docs/auth/jwt/oidc-providers)
- [Azure AD OIDC Integration](https://developer.hashicorp.com/vault/tutorials/auth-methods/oidc-auth-azure)
- [Azure AD App Registration](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)
