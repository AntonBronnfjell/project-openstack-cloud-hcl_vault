# ============================================================================
# Vault Service Leaf Module - Provider Configuration
# ============================================================================
# This module receives the OpenStack provider from the root repository
# via the providers block. The provider is configured globally in the root.

terraform {
  required_version = ">= 1.0"

  # Backend: s3 (OpenStack Swift S3-compatible bucket). Config via -backend-config=backend.s3.hcl
  # See backend.s3.hcl for configuration details.
  backend "s3" {}

  required_providers {
    openstack = {
      source                = "terraform-provider-openstack/openstack"
      version               = "~> 1.54.0"
      configuration_aliases = [openstack]
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# Provider alias for receiving OpenStack provider from root module
# The provider configuration comes from the root repository's provider.tf
# This allows centralized credential management
