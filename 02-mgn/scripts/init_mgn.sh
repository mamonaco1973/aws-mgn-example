#!/bin/bash
set -euo pipefail

AWS_REGION="$1"
STAGING_SUBNET_ID="$2"
REPLICATION_INSTANCE_TYPE="$3"
USE_PRIVATE_IP="$4"
TARGET_SECURITY_GROUP_ID="$5"

echo "=============================================================="
echo "Initializing AWS MGN in region: ${AWS_REGION}"
echo "=============================================================="

aws mgn initialize-service \
  --region "${AWS_REGION}" || true

echo "=============================================================="
echo "Updating replication configuration template"
echo "=============================================================="

TEMPLATE_ID="$(aws mgn describe-replication-configuration-templates \
  --region "${AWS_REGION}" \
  --query 'items[0].replicationConfigurationTemplateID' \
  --output text)"

if [ -z "${TEMPLATE_ID}" ] || [ "${TEMPLATE_ID}" = "None" ]; then
  echo "ERROR: No replication configuration template found."
  exit 1
fi

aws mgn update-replication-configuration-template \
  --region "${AWS_REGION}" \
  --replication-configuration-template-id "${TEMPLATE_ID}" \
  --staging-area-subnet-id "${STAGING_SUBNET_ID}" \
  --replication-server-instance-type "${REPLICATION_INSTANCE_TYPE}" \
  --use-private-ip-for-replication "${USE_PRIVATE_IP}"

echo "=============================================================="
echo "Reading launch configuration templates"
echo "=============================================================="

aws mgn describe-launch-configuration-templates \
  --region "${AWS_REGION}" \
  --output table || true

echo "=============================================================="
echo "MGN initialization complete"
echo "=============================================================="