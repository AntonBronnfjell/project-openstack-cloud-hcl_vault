# ============================================================================
# Vault Service Leaf Module - Outputs
# ============================================================================

# Instance IPs for load balancing
output "instance_ips" {
  description = "List of Vault instance IP addresses"
  value       = [for instance in openstack_compute_instance_v2.vault : instance.network[0].fixed_ip_v4]
}

# Instance details
output "instances" {
  description = "Vault instance details"
  value = {
    for idx, instance in openstack_compute_instance_v2.vault :
    "vault-${idx + 1}" => {
      id        = instance.id
      name      = instance.name
      ip        = instance.network[0].fixed_ip_v4
      status    = instance.status
      port      = var.vault_port
      health_url = "https://${instance.network[0].fixed_ip_v4}:${var.vault_port}/v1/sys/health"
    }
  }
}

# Local value for service definition (uses instance_ips from docker-deploy.tf)
locals {
  instance_ips_for_output = [for instance in openstack_compute_instance_v2.vault : instance.network[0].fixed_ip_v4]
  
  # Service definition YAML
  service_yaml = yamlencode({
    metadata = {
      name         = "vault"
      display_name = "HashiCorp Vault"
      description  = "Secret management service deployed on OpenStack"
      version      = var.vault_version
      repository   = "openstack-infra"
    }
    domain = {
      subdomain  = var.subdomain
      domain     = var.domain
      path_prefix = ""
    }
    backend = {
      type                = "https"
      host                = length(local.instance_ips_for_output) > 0 ? local.instance_ips_for_output[0] : ""
      port                = var.vault_port
      path                = ""
      protocol            = "https"
      insecure_skip_verify = true
      load_balancer = {
        method = "roundrobin"
        servers = [
          for ip in local.instance_ips_for_output : {
            url = "https://${ip}:${var.vault_port}"
          }
        ]
        health_check = {
          enabled         = true
          path            = "/v1/sys/health"
          interval        = "30s"
          timeout         = "5s"
          expected_status = 200
        }
      }
    }
    traefik = {
      entrypoints = ["web", "websecure"]
      middlewares = []
      tls = {
        enabled = false
      }
      priority      = 0
      router_name   = "${var.subdomain}-router"
      service_name  = "${var.subdomain}-service"
      transport_name = "${var.subdomain}-transport"
    }
    cloudflare = {
      dns = {
        create_record = true
        proxied       = true
        ttl           = 1
      }
      tunnel = {
        enabled = true
        origin_request = {
          http_host_header   = ""
          origin_server_name = ""
        }
      }
      access = {
        enabled            = false
        application_name   = "Vault Service"
        session_duration   = "24h"
        app_launcher_visible = false
        policies           = []
      }
    }
    env = {
      TARGET_SERVER = length(local.instance_ips_for_output) > 0 ? local.instance_ips_for_output[0] : ""
      TARGET_PORT   = tostring(var.vault_port)
      DOMAIN        = var.domain
    }
    tags         = ["infrastructure", "secrets", "security", "vault"]
    dependencies = []
    health_check = {
      enabled         = true
      path            = "/v1/sys/health"
      method          = "GET"
      expected_status = 200
      interval        = "30s"
      timeout         = "5s"
    }
  })
}

# Service definition for root consumption (YAML format)
output "service" {
  description = "Vault service definition in YAML format for root repository"
  value = local.service_yaml
}

# Services map (for compatibility with root repository service discovery)
output "services" {
  description = "Services map for root repository consumption"
  value = {
    vault = yamldecode(local.service_yaml)
  }
}

# Connection details
output "connection_details" {
  description = "Vault connection details"
  value = {
    domain        = var.domain
    subdomain     = var.subdomain
    full_domain   = "${var.subdomain}.${var.domain}"
    instance_ips  = local.instance_ips_for_output
    vault_port    = var.vault_port
    vault_addr    = var.vault_addr
    vault_api_addr = var.vault_api_addr
    health_endpoints = [
      for ip in local.instance_ips_for_output : "https://${ip}:${var.vault_port}/v1/sys/health"
    ]
  }
}

# Security group ID
output "security_group_id" {
  description = "Vault security group ID"
  value       = openstack_networking_secgroup_v2.vault.id
}
