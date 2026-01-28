# ============================================================================
# Vault Helm Chart Deployment
# ============================================================================
# Migrates Vault from Docker Compose to Kubernetes using Helm

# Namespace for Vault
resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
  }
}

# Secret for Azure AD OIDC credentials
resource "kubernetes_secret" "vault_azure_ad_oidc" {
  depends_on = [kubernetes_namespace.vault]
  count      = var.enable_azure_ad_oidc ? 1 : 0

  metadata {
    name      = "vault-azure-ad-oidc"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  data = {
    client_id     = base64encode(var.azure_ad_client_id != "" ? var.azure_ad_client_id : "")
    client_secret = base64encode(var.azure_ad_client_secret != "" ? var.azure_ad_client_secret : "")
    tenant_id     = base64encode(var.azure_ad_tenant_id != "" ? var.azure_ad_tenant_id : "")
  }

  type = "Opaque"
}

# Secret for Vault TLS certificates (if provided)
resource "kubernetes_secret" "vault_tls" {
  depends_on = [kubernetes_namespace.vault]
  count      = var.enable_tls && var.tls_cert_path != "" && var.tls_key_path != "" ? 1 : 0

  metadata {
    name      = "vault-tls"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  data = {
    "vault-cert.pem" = base64encode(file(var.tls_cert_path))
    "vault-key.pem" = base64encode(file(var.tls_key_path))
  }

  type = "Opaque"
}

# Helm release for Vault
resource "helm_release" "vault" {
  depends_on = [
    kubernetes_namespace.vault,
    kubernetes_secret.vault_tls,
    null_resource.k3s_master_ready
  ]

  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = var.vault_helm_version
  namespace  = kubernetes_namespace.vault.metadata[0].name

  values = [
    file("${path.module}/helm-values.yaml")
  ]

  # Wait for deployment to be ready
  wait    = true
  timeout = 600

  lifecycle {
    create_before_destroy = true
  }
}

# PodDisruptionBudget for Vault
resource "kubernetes_pod_disruption_budget_v1" "vault" {
  depends_on = [helm_release.vault]

  metadata {
    name      = "vault-pdb"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  spec {
    min_available = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "vault"
        "app.kubernetes.io/instance" = "vault"
        "component"                  = "server"
      }
    }
  }
}

# Kubernetes Job for Vault initialization (replaces shell script)
resource "kubernetes_job_v1" "vault_init" {
  depends_on = [helm_release.vault]
  count      = 1  # Only initialize once

  metadata {
    name      = "vault-init"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  spec {
    ttl_seconds_after_finished = 3600  # Clean up after 1 hour

    template {
      metadata {
        labels = {
          app = "vault-init"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "vault-init"
          image = "hashicorp/vault:${var.vault_version}"

          command = [
            "sh",
            "-c",
            <<-EOT
              set -e
              echo "Initializing Vault..."
              
              # Wait for Vault to be ready
              until vault status 2>/dev/null | grep -q "Initialized.*true\|Initialized.*false"; do
                echo "Waiting for Vault to be ready..."
                sleep 5
              done
              
              # Check if already initialized
              if vault status 2>/dev/null | grep -q "Initialized.*true"; then
                echo "Vault is already initialized"
                exit 0
              fi
              
              # Initialize Vault
              vault operator init -key-shares=5 -key-threshold=3 -format=json > /tmp/vault-init.json || {
                echo "Vault initialization failed or already initialized"
                exit 0
              }
              
              echo "Vault initialized successfully"
              echo "Unseal keys and root token saved to /tmp/vault-init.json"
            EOT
          }

          env {
            name  = "VAULT_ADDR"
            value = "https://vault.vault.svc.cluster.local:8200"
          }

          env {
            name  = "VAULT_SKIP_VERIFY"
            value = "true"
          }

          volume_mount {
            name       = "vault-init-data"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "vault-init-data"
          empty_dir {}
        }
      }
    }
  }
}

# Kubernetes Job for Vault OIDC configuration (replaces configure-vault-oidc.sh)
resource "kubernetes_job_v1" "vault_oidc_config" {
  depends_on = [
    helm_release.vault,
    kubernetes_job_v1.vault_init,
    kubernetes_secret.vault_azure_ad_oidc
  ]
  count = var.enable_azure_ad_oidc ? 1 : 0

  metadata {
    name      = "vault-oidc-config"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  spec {
    ttl_seconds_after_finished = 3600  # Clean up after 1 hour

    template {
      metadata {
        labels = {
          app = "vault-oidc-config"
        }
      }

      spec {
        restart_policy = "Never"

        container {
          name  = "vault-oidc-config"
          image = "hashicorp/vault:${var.vault_version}"

          command = [
            "sh",
            "-c",
            <<-EOT
              set -e
              echo "Configuring Vault OIDC with Azure AD..."
              
              # Wait for Vault to be ready and unsealed
              MAX_RETRIES=60
              RETRY_COUNT=0
              while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                if vault status 2>/dev/null | grep -q "Sealed.*false"; then
                  echo "Vault is ready and unsealed"
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
                oidc_client_id="${var.azure_ad_client_id}" \
                oidc_client_secret="${var.azure_ad_client_secret}" \
                oidc_discovery_url="https://login.microsoftonline.com/${var.azure_ad_tenant_id}/v2.0" \
                default_role="${var.vault_oidc_default_role}"
              
              # Create default OIDC role
              echo "Creating OIDC role: ${var.vault_oidc_default_role}..."
              vault write auth/oidc/role/${var.vault_oidc_default_role} \
                user_claim="email" \
                groups_claim="groups" \
                bound_audiences="${var.azure_ad_client_id}" \
                allowed_redirect_uris="https://chisel.graphicsforge.net/ui/vault/auth/oidc/oidc/callback" \
                allowed_redirect_uris="https://chisel.graphicsforge.net/oidc/callback" \
                allowed_redirect_uris="http://localhost:8250/oidc/callback" \
                token_policies="default"
              
              echo "Azure AD OIDC configuration complete!"
            EOT
          }

          env {
            name  = "VAULT_ADDR"
            value = "https://vault.vault.svc.cluster.local:8200"
          }

          env {
            name  = "VAULT_SKIP_VERIFY"
            value = "true"
          }

          env {
            name  = "OIDC_CLIENT_ID"
            value = var.azure_ad_client_id
          }

          env {
            name  = "OIDC_CLIENT_SECRET"
            value = var.azure_ad_client_secret
          }

          env {
            name  = "OIDC_TENANT_ID"
            value = var.azure_ad_tenant_id
          }
        }
      }
    }
  }
}
