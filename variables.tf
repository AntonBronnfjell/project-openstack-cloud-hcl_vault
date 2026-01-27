# ============================================================================
# Vault Service Leaf Module - Variables
# ============================================================================

variable "domain" {
  description = "Domain name for the Vault service (e.g., graphicsforge.net)"
  type        = string
}

variable "subdomain" {
  description = "Subdomain for Vault service (e.g., chisel for chisel.graphicsforge.net)"
  type        = string
  default     = "chisel"
}

variable "instance_count" {
  description = "Number of Vault instances to deploy for high availability (minimum 2 for zero-downtime)"
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1
    error_message = "At least 1 instance is required. Use 2+ for zero-downtime deployments."
  }
}

variable "instance_flavor" {
  description = "OpenStack flavor (instance type) for Vault instances"
  type        = string
  default     = "m1.small"
}

variable "instance_image" {
  description = "OpenStack image ID or name for Vault instances (Ubuntu/Debian with cloud-init)"
  type        = string
  default     = "ubuntu-22.04"
}

variable "network_name" {
  description = "OpenStack network name to attach instances to"
  type        = string
  default     = ""
}

variable "network_id" {
  description = "OpenStack network ID to attach instances to (alternative to network_name)"
  type        = string
  default     = ""
}

variable "security_group_name" {
  description = "Name for the Vault security group"
  type        = string
  default     = "vault-sg"
}

variable "ssh_key_name" {
  description = "OpenStack SSH key pair name for instance access"
  type        = string
}

variable "vault_port" {
  description = "Port on which Vault listens (default: 8200)"
  type        = number
  default     = 8200
}

variable "vault_data_path" {
  description = "Path on instance for Vault data storage"
  type        = string
  default     = "/opt/vault/data"
}

variable "vault_config_path" {
  description = "Path on instance for Vault configuration"
  type        = string
  default     = "/opt/vault/config"
}

variable "vault_version" {
  description = "Vault Docker image version"
  type        = string
  default     = "latest"
}

variable "enable_tls" {
  description = "Enable TLS for Vault (requires certificates)"
  type        = bool
  default     = true
}

variable "tls_cert_path" {
  description = "Path to TLS certificate file (if using file-based certs)"
  type        = string
  default     = ""
}

variable "tls_key_path" {
  description = "Path to TLS private key file (if using file-based certs)"
  type        = string
  default     = ""
}

variable "vault_addr" {
  description = "Vault API address (full URL)"
  type        = string
}

variable "vault_api_addr" {
  description = "Vault API address (full URL)"
  type        = string
}

variable "deploy_user" {
  description = "SSH user for deployment (default: ubuntu)"
  type        = string
  default     = "ubuntu"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for instance access"
  type        = string
  default     = ""
}

# ============================================================================
# Azure AD OIDC Configuration
# ============================================================================

variable "azure_ad_tenant_id" {
  description = "Azure AD tenant ID for OIDC authentication"
  type        = string
  sensitive   = true
}

variable "azure_ad_client_id" {
  description = "Azure AD application (client) ID for OIDC authentication"
  type        = string
  sensitive   = true
}

variable "azure_ad_client_secret" {
  description = "Azure AD client secret for OIDC authentication"
  type        = string
  sensitive   = true
}

variable "enable_azure_ad_oidc" {
  description = "Enable Azure AD OIDC authentication"
  type        = bool
  default     = true
}

variable "vault_oidc_default_role" {
  description = "Default OIDC role name for Azure AD authentication"
  type        = string
  default     = "azure-ad"
}

variable "vault_oidc_bound_audiences" {
  description = "Bound audiences for OIDC (typically the client ID). If empty, uses azure_ad_client_id"
  type        = list(string)
  default     = []
}
