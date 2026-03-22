#!/bin/bash
set -euo pipefail

# ================================================================================
# destroy.sh
#
# Tears down both Terraform phases in reverse order:
#   Phase 2 — 02-source : EC2 source VM and networking destroyed first
#   Phase 1 — 01-mgn    : MGN, IAM, and VPC destroyed second
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
# MGN EC2 Instance Termination
# MGN tags every instance it launches (test instances, replication servers,
# conversion servers) with AWSApplicationMigrationServiceManaged=mgn.amazonaws.com.
# Terminate them all in one pass before destroying the VPC or the destroy will
# fail on dependency violations.
# --------------------------------------------------------------------------------
echo "NOTE: Terminating all MGN-managed EC2 instances in ${MGN_REGION}..."

MGN_INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "${MGN_REGION}" \
  --filters \
    "Name=tag:AWSApplicationMigrationServiceManaged,Values=mgn.amazonaws.com" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text 2>/dev/null | tr '\t' '\n' | grep '^i-' | sort -u || true)

if [[ -n "${MGN_INSTANCE_IDS}" ]]; then
  echo "NOTE: Terminating instances: $(echo "${MGN_INSTANCE_IDS}" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  aws ec2 terminate-instances \
    --region "${MGN_REGION}" \
    --instance-ids ${MGN_INSTANCE_IDS} > /dev/null

  echo "NOTE: Waiting for instances to terminate..."
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated \
    --region "${MGN_REGION}" \
    --instance-ids ${MGN_INSTANCE_IDS}

  echo "NOTE: All MGN-managed instances terminated."
else
  echo "NOTE: No MGN-managed instances found."
fi

# --------------------------------------------------------------------------------
# MGN Job Cleanup
# MGN jobs (test launches, cutover launches) are not managed by Terraform.
# Delete all completed/failed jobs before tearing down MGN resources.
# --------------------------------------------------------------------------------
echo "NOTE: Deleting MGN jobs in ${MGN_REGION}..."

JOB_IDS=$(aws mgn describe-jobs \
  --region "${MGN_REGION}" \
  --query 'items[*].jobID' \
  --output text 2>/dev/null || true)

if [[ -n "${JOB_IDS}" ]]; then
  for JOB_ID in ${JOB_IDS}; do
    echo "NOTE: Deleting job ${JOB_ID}..."
    aws mgn delete-job \
      --region "${MGN_REGION}" \
      --job-id "${JOB_ID}" 2>/dev/null || true
  done
else
  echo "NOTE: No MGN jobs found."
fi

# --------------------------------------------------------------------------------
# MGN Conversion Server Security Group Deletion
# MGN creates this security group automatically — it is not managed by
# Terraform and must be deleted after conversion servers are terminated
# or the VPC destroy will fail on a dependency violation.
# --------------------------------------------------------------------------------
echo "NOTE: Deleting MGN conversion server security group in ${MGN_REGION}..."

CONVERSION_SG_ID=$(aws ec2 describe-security-groups \
  --region "${MGN_REGION}" \
  --filters \
    "Name=group-name,Values=AWS Application Migration Service default Conversion Server Security Group" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)

if [[ -n "${CONVERSION_SG_ID}" && "${CONVERSION_SG_ID}" != "None" ]]; then
  echo "NOTE: Deleting security group ${CONVERSION_SG_ID}..."
  aws ec2 delete-security-group \
    --region "${MGN_REGION}" \
    --group-id "${CONVERSION_SG_ID}"
  echo "NOTE: Security group deleted."
else
  echo "NOTE: No MGN conversion server security group found."
fi

# --------------------------------------------------------------------------------
# Phase 2 — AWS source environment (us-east-2)
# Destroy source instances before MGN infrastructure — reverse of build order.
# --------------------------------------------------------------------------------
echo "NOTE: Destroying 02-source..."
terraform -chdir="${SCRIPT_DIR}/02-source" init
terraform -chdir="${SCRIPT_DIR}/02-source" destroy -auto-approve

# --------------------------------------------------------------------------------
# Phase 1 — AWS MGN target environment (us-east-1)
# Destroy after source instances are gone so IAM roles and Secrets Manager
# secret are still in place for the MGN cleanup calls above.
# --------------------------------------------------------------------------------
echo "NOTE: Destroying 01-mgn..."
terraform -chdir="${SCRIPT_DIR}/01-mgn" init
terraform -chdir="${SCRIPT_DIR}/01-mgn" destroy -auto-approve

echo "NOTE: Teardown complete."
