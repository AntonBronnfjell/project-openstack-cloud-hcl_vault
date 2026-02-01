#!/usr/bin/env bash
# ============================================================================
# Automatically Destroy Old Deposed Vault Instances
# ============================================================================
# This script destroys the old vault instances that were replaced but not destroyed.
# These instances are no longer tracked in Terraform state.

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Destroying Old Vault Instances ===${NC}"
echo ""

# Old instance IDs (from the backup state file)
OLD_INSTANCES=(
  "9edf98c1-f8ec-4651-a010-0bf75495cb88"  # vault-1 at 10.0.0.172
  "26176b28-0240-4bac-acbd-454b4b5b2c8e"  # vault-2 at 10.0.0.253
)

# Check if OpenStack CLI is available
if ! command -v openstack &> /dev/null; then
  echo -e "${RED}Error: OpenStack CLI not found${NC}"
  echo "Please install python-openstackclient or source your OpenStack credentials"
  echo "Example: source /root/openrc"
  exit 1
fi

# Destroy each old instance
for instance_id in "${OLD_INSTANCES[@]}"; do
  echo -e "${YELLOW}Destroying instance: $instance_id${NC}"
  
  # Check if instance exists
  if ! openstack server show "$instance_id" &>/dev/null; then
    echo -e "${GREEN}  ✓ Instance $instance_id already deleted${NC}"
    continue
  fi
  
  # Get instance name for confirmation
  instance_name=$(openstack server show "$instance_id" -f value -c name 2>/dev/null || echo "unknown")
  instance_ip=$(openstack server show "$instance_id" -f value -c addresses 2>/dev/null | grep -oE '10\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  
  echo "  Name: $instance_name"
  echo "  IP: $instance_ip"
  
  # Destroy the instance
  if openstack server delete "$instance_id" 2>/dev/null; then
    echo -e "${GREEN}  ✓ Instance $instance_id destroyed${NC}"
  else
    echo -e "${RED}  ✗ Failed to destroy instance $instance_id${NC}"
  fi
  echo ""
done

echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo ""
echo "Remaining instances should be:"
echo "  - vault-1: 10.0.0.50"
echo "  - vault-2: 10.0.0.101"
