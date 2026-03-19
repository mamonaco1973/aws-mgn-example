#!/bin/bash
set -euo pipefail

# ================================================================================
# destroy.sh
#
# Tears down both Terraform phases in reverse order:
#   Phase 2 — 02-mgn    : AWS resources destroyed first (MGN, IAM, VPC)
#   Phase 1 — 01-source : EC2 source VM and networking destroyed second
#
# MGN source servers must be deleted before Terraform runs — they are not
# managed by Terraform and will block IAM role deletion if left behind.
# ================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MGN_REGION="us-east-1"

# --------------------------------------------------------------------------------
# MGN Source Server Cleanup
# Disconnect, archive, then delete all source servers in the account.
# Must run before Terraform so IAM roles are still in place for the API calls.
# --------------------------------------------------------------------------------
echo "NOTE: Cleaning up MGN source servers in ${MGN_REGION}..."

SOURCE_SERVER_IDS=$(aws mgn describe-source-servers \
  --region "${MGN_REGION}" \
  --filters '{}' \
  --query 'items[*].sourceServerID' \
  --output text 2>/dev/null || true)

if [[ -n "${SOURCE_SERVER_IDS}" ]]; then

  # Disconnect any servers still reporting to MGN before archiving.
  for ID in ${SOURCE_SERVER_IDS}; do
    echo "NOTE: Disconnecting source server ${ID}..."
    aws mgn disconnect-from-service \
      --region "${MGN_REGION}" \
      --source-server-id "${ID}" 2>/dev/null || true
  done

  # Archive all servers — delete-source-server requires archived state.
  for ID in ${SOURCE_SERVER_IDS}; do
    echo "NOTE: Archiving source server ${ID}..."
    aws mgn archive-source-server \
      --region "${MGN_REGION}" \
      --source-server-id "${ID}" 2>/dev/null || true
  done

  # Delete all archived servers.
  for ID in ${SOURCE_SERVER_IDS}; do
    echo "NOTE: Deleting source server ${ID}..."
    aws mgn delete-source-server \
      --region "${MGN_REGION}" \
      --source-server-id "${ID}"
  done

else
  echo "NOTE: No MGN source servers found."
fi

# --------------------------------------------------------------------------------
# Phase 2 — AWS MGN target environment
# Destroy AWS side first to cleanly remove IAM roles and the Secrets Manager
# secret before tearing down the source VM.
# --------------------------------------------------------------------------------
echo "NOTE: Destroying 02-mgn..."
terraform -chdir="${SCRIPT_DIR}/02-mgn" init
terraform -chdir="${SCRIPT_DIR}/02-mgn" destroy -auto-approve

# --------------------------------------------------------------------------------
# Phase 1 — AWS source environment (us-east-2)
# --------------------------------------------------------------------------------
echo "NOTE: Destroying 01-source..."
terraform -chdir="${SCRIPT_DIR}/01-source" init
terraform -chdir="${SCRIPT_DIR}/01-source" destroy -auto-approve

echo "NOTE: Teardown complete."
