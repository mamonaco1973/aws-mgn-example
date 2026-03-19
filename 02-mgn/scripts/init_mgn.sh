#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="$1"
STAGING_SUBNET_ID="$2"
TARGET_SECURITY_GROUP_ID="$3"
REPLICATION_INSTANCE_TYPE="$4"

echo "=============================================================="
echo "AWS MGN Initialization (clean rebuild)"
echo "Region                    : ${AWS_REGION}"
echo "Staging Subnet            : ${STAGING_SUBNET_ID}"
echo "Replication Security Group: ${TARGET_SECURITY_GROUP_ID}"
echo "Replication Instance Type : ${REPLICATION_INSTANCE_TYPE}"
echo "=============================================================="

# --------------------------------------------------------------
# Initialize service
# --------------------------------------------------------------

echo "Initializing MGN service..."

aws mgn initialize-service \
  --region "${AWS_REGION}" \
  >/dev/null 2>&1 || true

# --------------------------------------------------------------
# Delete existing replication configuration template
# --------------------------------------------------------------

echo "Checking for existing replication templates..."

EXISTING_REPLICATION_TEMPLATE=$(aws mgn describe-replication-configuration-templates \
  --region "${AWS_REGION}" \
  --query "items[0].replicationConfigurationTemplateID" \
  --output text 2>/dev/null || true)

if [[ "${EXISTING_REPLICATION_TEMPLATE}" != "None" && -n "${EXISTING_REPLICATION_TEMPLATE}" ]]; then

  echo "Deleting existing replication template: ${EXISTING_REPLICATION_TEMPLATE}"

  aws mgn delete-replication-configuration-template \
    --region "${AWS_REGION}" \
    --replication-configuration-template-id "${EXISTING_REPLICATION_TEMPLATE}"

fi

# --------------------------------------------------------------
# Delete existing launch configuration template
# --------------------------------------------------------------

echo "Checking for existing launch templates..."

EXISTING_LAUNCH_TEMPLATE=$(aws mgn describe-launch-configuration-templates \
  --region "${AWS_REGION}" \
  --query "items[0].launchConfigurationTemplateID" \
  --output text 2>/dev/null || true)

if [[ "${EXISTING_LAUNCH_TEMPLATE}" != "None" && -n "${EXISTING_LAUNCH_TEMPLATE}" ]]; then

  echo "Deleting existing launch template: ${EXISTING_LAUNCH_TEMPLATE}"

  aws mgn delete-launch-configuration-template \
    --region "${AWS_REGION}" \
    --launch-configuration-template-id "${EXISTING_LAUNCH_TEMPLATE}"

fi

# --------------------------------------------------------------
# Create replication configuration template
# --------------------------------------------------------------

echo "Creating replication configuration template..."

aws mgn create-replication-configuration-template \
  --region "${AWS_REGION}" \
  --staging-area-subnet-id "${STAGING_SUBNET_ID}" \
  --replication-servers-security-groups-ids "${TARGET_SECURITY_GROUP_ID}" \
  --replication-server-instance-type "${REPLICATION_INSTANCE_TYPE}" \
  --use-dedicated-replication-server \
  --data-plane-routing PUBLIC_IP \
  --create-public-ip \
  --default-large-staging-disk-type GP2 \
  --ebs-encryption DEFAULT \
  --bandwidth-throttling 0 \
  --staging-area-tags Name=mgn-staging,Project=mgn-lab

# --------------------------------------------------------------
# Create launch configuration template
# --------------------------------------------------------------

echo "Creating launch configuration template..."

aws mgn create-launch-configuration-template \
  --region "${AWS_REGION}" \
  --boot-mode UEFI \
  --copy-private-ip \
  --copy-tags \
  --launch-disposition STOPPED \
  --licensing-os-byol false \
  --target-instance-type-right-sizing-method NONE

# --------------------------------------------------------------
# Show final state
# --------------------------------------------------------------

echo
echo "=============================================================="
echo "MGN Replication Template"
echo "=============================================================="

aws mgn describe-replication-configuration-templates \
  --region "${AWS_REGION}" \
  --query "items[*].{ID:replicationConfigurationTemplateID,Subnet:stagingAreaSubnetId,SG:replicationServersSecurityGroupsIDs[0]}" \
  --output table

echo
echo "=============================================================="
echo "MGN Launch Template"
echo "=============================================================="

aws mgn describe-launch-configuration-templates \
  --region "${AWS_REGION}" \
  --query "items[*].{ID:launchConfigurationTemplateID,Disposition:launchDisposition}" \
  --output table

echo
echo "=============================================================="
echo "MGN initialization complete"
echo "=============================================================="