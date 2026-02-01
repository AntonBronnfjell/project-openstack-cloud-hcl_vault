# Vault Service Leaf Module

Terraform module for deploying HashiCorp Vault as a high-availability service on OpenStack infrastructure.

## Overview

This module creates multiple Vault instances on OpenStack for zero-downtime deployments. It integrates with the root repository (`project-traefik-container-yaml_domain-reverse-proxy`) to provide service definitions for Traefik routing.

## Features

- **High Availability**: Deploys multiple Vault instances (default: 2) for zero-downtime
- **Docker-based**: Uses Docker Compose for container management (Kubernetes removed)
- **TLS Support**: Configurable TLS certificates for secure communication
- **Auto-discovery**: Outputs service definitions for root repository consumption
- **Health Checks**: Built-in health check endpoints for load balancing
- **Azure AD OIDC**: Integrated Azure AD authentication support

## Usage

### As a Leaf Module (Recommended)

This module is designed to be referenced from the root repository:

```hcl
module "vault_service" {
  source = "git::https://github.com/AntonBronnfjell/project-openstack-cloud-hcl_vault.git?ref=main"
  
  domain  = "graphicsforge.net"
  subdomain = "chisel"
  
  instance_count = 2
  ssh_key_name   = "your-ssh-key"
  
  vault_addr    = "https://chisel.graphicsforge.net"
  vault_api_addr = "https://chisel.graphicsforge.net"
  
  providers = {
    openstack = openstack  # Provider from root repository
  }
}
```

### Standalone Usage

```hcl
terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54.0"
    }
  }
}

provider "openstack" {
  cloud = "openstack"  # From clouds.yaml
}

module "vault" {
  source = "./project-openstack-cloud-hcl_vault"
  
  domain  = "graphicsforge.net"
  subdomain = "chisel"
  
  instance_count = 2
  ssh_key_name   = "your-ssh-key"
  
  vault_addr    = "https://chisel.graphicsforge.net"
  vault_api_addr = "https://chisel.graphicsforge.net"
}
```

### Remote state (optional)

To use OpenStack object storage for Terraform state: create the bucket via `project-openstack-cloud-bucket_terraform-state`, store credentials in Vault at `terraform-state/credentials/env-s3`, copy `backend.s3.example` to `backend.s3.hcl`, fill from Vault (e.g. run `vault-secrets-fetch.sh` from the traefik repo), and run `terraform init -backend-config=backend.s3.hcl`. See that repo’s docs/VAULT_SECRETS.md and QUICKSTART.

## Requirements

- Terraform >= 1.0
- OpenStack provider >= 1.54.0
- OpenStack access with compute and networking permissions
- SSH key pair in OpenStack
- Docker-enabled image (Ubuntu 22.04 recommended)

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| domain | Domain name for the Vault service | string | - | yes |
| subdomain | Subdomain for Vault service | string | "chisel" | no |
| instance_count | Number of Vault instances (2+ for HA) | number | 2 | no |
| instance_flavor | OpenStack flavor for instances | string | "m1.small" | no |
| instance_image | OpenStack image name/ID | string | "ubuntu-22.04" | no |
| network_name | OpenStack network name | string | "private" | no |
| ssh_key_name | OpenStack SSH key pair name | string | - | yes |
| vault_port | Vault listening port | number | 8200 | no |
| vault_addr | Vault API address (full URL) | string | - | yes |
| vault_api_addr | Vault API address (full URL) | string | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| instance_ips | List of Vault instance IP addresses |
| services | Service definitions map for root consumption |
| connection_details | Vault connection details |
| security_group_id | Vault security group ID |

## Architecture

```
OpenStack Infrastructure
├── Instance 1 (vault-1)
│   ├── Docker Compose
│   └── Vault Container (port 8200)
├── Instance 2 (vault-2)
│   ├── Docker Compose
│   └── Vault Container (port 8200)
└── Security Group
    ├── SSH (22)
    ├── Vault HTTPS (8200)
    └── Vault Cluster (8201)
```

## Zero-Downtime Deployment

The module implements zero-downtime deployment through:

1. **Multiple Instances**: Deploys 2+ instances for redundancy
2. **Lifecycle Management**: Uses `create_before_destroy` for safe updates
3. **Health Checks**: Verifies instances are healthy before removing old ones
4. **Load Balancing**: Traefik distributes traffic across healthy instances

## TLS Configuration

TLS certificates can be provided via:
- File paths (`tls_cert_path`, `tls_key_path`)
- Self-signed certificates (generated on instances)
- External certificate management

## Integration with Root Repository

The module outputs service definitions in YAML format that are automatically consumed by the root repository for:
- Traefik routing configuration
- Cloudflare DNS and tunnel setup
- Service discovery

## Security Considerations

- Security groups restrict access to necessary ports only
- TLS encryption for Vault communication
- SSH access for deployment only
- Vault data stored in persistent volumes

## License

MIT
