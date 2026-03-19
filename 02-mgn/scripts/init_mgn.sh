#!/bin/bash
set -euo pipefail

AWS_REGION="$1"
STAGING_SUBNET_ID="$2"
TARGET_SECURITY_GROUP_ID="$3"
REPLICATION_INSTANCE_TYPE="$4"
USE_PRIVATE_IP="$5"

echo "=============================================================="
echo "Initializing AWS MGN in region: ${AWS_REGION}"
echo "=============================================================="

# ------------------------------------------------------------------
# Initialize the service
# ------------------------------------------------------------------

aws mgn initialize-service \
  --region "${AWS_REGION}"

# ------------------------------------------------------------------
# Create the replication configuration template
# ------------------------------------------------------------------

echo "=============================================================="
echo "Creating replication configuration template"
echo "=============================================================="

aws mgn create-replication-configuration-template \
  --region "${AWS_REGION}" \
  --associate-default-security-group \
  --bandwidth-throttling 0 \
  --create-public-ip \
  --data-plane-routing PRIVATE_IP \
  --default-large-staging-disk-type GP2 \
  --ebs-encryption DEFAULT \
  --replication-server-instance-type "${REPLICATION_INSTANCE_TYPE}" \
  --replication-servers-security-groups-ids "${TARGET_SECURITY_GROUP_ID}" \
  --staging-area-subnet-id "${STAGING_SUBNET_ID}" \
  --staging-area-tags Name=mgn-staging,Project=mgn-lab \
  --use-dedicated-replication-server \
  >/tmp/mgn-replication-template.json 2>/tmp/mgn-replication-template.err || true

# ------------------------------------------------------------------
# If the template already exists, do not fail the run
# ------------------------------------------------------------------

if aws mgn describe-replication-configuration-templates \
  --region "${AWS_REGION}" \
  --query 'items[0].replicationConfigurationTemplateID' \
  --output text >/tmp/mgn-template-id.txt 2>/dev/null; then
  echo "Replication template exists."
else
  echo "ERROR: Failed to verify replication template."
  cat /tmp/mgn-replication-template.err || true
  exit 1
fi

# ------------------------------------------------------------------
# Create the launch configuration template
# ------------------------------------------------------------------

echo "=============================================================="
echo "Creating launch configuration template"
echo "=============================================================="

aws mgn create-launch-configuration-template \
  --region "${AWS_REGION}" \
  --boot-mode UEFI \
  --copy-private-ip \
  --copy-tags \
  --launch-disposition STOPPED \
  --licensing-os-byol false \
  --target-instance-type-right-sizing-method NONE \
  >/tmp/mgn-launch-template.json 2>/tmp/mgn-launch-template.err || true

# ------------------------------------------------------------------
# Verify the launch configuration template exists
# ------------------------------------------------------------------

if aws mgn describe-launch-configuration-templates \
  --region "${AWS_REGION}" \
  --query 'items[0].launchConfigurationTemplateID' \
  --output text >/tmp/mgn-launch-template-id.txt 2>/dev/null; then
  echo "Launch template exists."
else
  echo "ERROR: Failed to verify launch configuration template."
  cat /tmp/mgn-launch-template.err || true
  exit 1
fi

echo "=============================================================="
echo "AWS MGN initialization complete"
echo "=============================================================="