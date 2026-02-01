#!/usr/bin/env bash
# ============================================================================
# Cleanup Duplicate Vault Instances and Rename MinIO Instance
# ============================================================================
# This script:
# 1. Destroys old duplicate vault instances (10.0.0.172 and 10.0.0.253)
# 2. Renames minio-1 instance to swift-object-storage

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Cleanup and Rename Script ===${NC}"
echo ""

# Check if OpenStack CLI is available
if ! command -v openstack &> /dev/null; then
  echo -e "${RED}Error: OpenStack CLI not found${NC}"
  echo "Please install python-openstackclient or source your OpenStack credentials"
  echo "Example: source /root/openrc"
  exit 1
fi

# Old vault instance IDs to destroy
OLD_VAULT_INSTANCES=(
  "9edf98c1-f8ec-4651-a010-0bf75495cb88"  # vault-1 at 10.0.0.172
  "26176b28-0240-4bac-acbd-454b4b5b2c8e"  # vault-2 at 10.0.0.253
)

# Step 1: Destroy old duplicate vault instances
echo -e "${YELLOW}[1/2] Destroying old duplicate vault instances...${NC}"
for instance_id in "${OLD_VAULT_INSTANCES[@]}"; do
  echo -e "${YELLOW}  Checking instance: $instance_id${NC}"
  
  # Check if instance exists
  if ! openstack server show "$instance_id" &>/dev/null; then
    echo -e "${GREEN}    ✓ Instance $instance_id already deleted${NC}"
    continue
  fi
  
  # Get instance details
  instance_name=$(openstack server show "$instance_id" -f value -c name 2>/dev/null || echo "unknown")
  instance_ip=$(openstack server show "$instance_id" -f value -c addresses 2>/dev/null | grep -oE '10\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  
  echo "    Name: $instance_name"
  echo "    IP: $instance_ip"
  
  # Destroy the instance
  if openstack server delete "$instance_id" 2>/dev/null; then
    echo -e "${GREEN}    ✓ Instance $instance_id destroyed${NC}"
  else
    echo -e "${RED}    ✗ Failed to destroy instance $instance_id${NC}"
  fi
  echo ""
done

# Step 2: Rename minio-1 to swift-object-storage
echo -e "${YELLOW}[2/2] Renaming minio-1 instance to swift-object-storage...${NC}"

# Find minio-1 instance - try multiple methods
MINIO_INSTANCE_ID=$(openstack server list --name minio-1 -f value -c ID 2>/dev/null | head -1)

# If not found by exact name, try searching all instances
if [ -z "$MINIO_INSTANCE_ID" ]; then
  echo "  Searching for instances with 'minio' in name..."
  MINIO_INSTANCE_ID=$(openstack server list -f value -c ID -c Name 2>/dev/null | grep -i minio | head -1 | awk '{print $1}')
fi

# If still not found, list all instances to help debug
if [ -z "$MINIO_INSTANCE_ID" ]; then
  echo -e "${YELLOW}  ⊗ minio-1 instance not found by name${NC}"
  echo "  Listing all instances to find it:"
  openstack server list -f table -c ID -c Name -c Status 2>/dev/null | head -10
  echo ""
  echo "  Please provide the instance ID manually, or check if it's already renamed"
else
  echo "  Found minio instance: $MINIO_INSTANCE_ID"
  
  # Get current details
  current_name=$(openstack server show "$MINIO_INSTANCE_ID" -f value -c name 2>/dev/null || echo "unknown")
  current_ip=$(openstack server show "$MINIO_INSTANCE_ID" -f value -c addresses 2>/dev/null | grep -oE '10\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  
  echo "  Current name: $current_name"
  echo "  IP: $current_ip"
  
  # Rename the instance
  if openstack server set --name swift-object-storage "$MINIO_INSTANCE_ID" 2>/dev/null; then
    echo -e "${GREEN}  ✓ Instance renamed to swift-object-storage${NC}"
  else
    echo -e "${RED}  ✗ Failed to rename instance${NC}"
    echo "  Try manually: openstack server set --name swift-object-storage $MINIO_INSTANCE_ID"
  fi
fi

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo ""
echo "Summary:"
echo "  - Old vault instances destroyed (if they existed)"
echo "  - minio-1 renamed to swift-object-storage (if found)"
echo ""
echo "Remaining vault instances should be:"
echo "  - vault-1: 10.0.0.50"
echo "  - vault-2: 10.0.0.101"
