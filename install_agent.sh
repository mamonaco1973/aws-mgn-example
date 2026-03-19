#!/bin/bash
set -euo pipefail

# ================================================================================
# install_agent.sh
#
# Phase 3: Install the AWS MGN replication agent on the Azure source VM.
# Runs after 02-mgn apply so the agent credentials exist in Secrets Manager.
#
# Steps:
#   1. Resolve Azure VM FQDN from Terraform output (01-azure)
#   2. Fetch agent credentials from AWS Secrets Manager (mgn-agent-credentials)
#   3. SSH into the VM, download the MGN installer, and execute it as root
# ================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEM_FILE="${SCRIPT_DIR}/mgn-vm.pem"
AWS_REGION="us-east-1"
SECRET_NAME="mgn-agent-credentials"
SSH_USER="ubuntu"

# --------------------------------------------------------------------------------
# Resolve Azure VM FQDN from Terraform state
# --------------------------------------------------------------------------------
echo "NOTE: Reading VM FQDN from Terraform state..."
FQDN=$(terraform -chdir="${SCRIPT_DIR}/01-azure" output -raw vm_public_fqdn)

if [[ -z "${FQDN}" ]]; then
  echo "ERROR: could not retrieve vm_public_fqdn from Terraform output." >&2
  exit 1
fi

if [[ ! -f "${PEM_FILE}" ]]; then
  echo "ERROR: PEM key not found at ${PEM_FILE}" >&2
  exit 1
fi

echo "NOTE: Target VM: ${FQDN}"

# --------------------------------------------------------------------------------
# Fetch agent credentials from Secrets Manager
# The mgn-agent-credentials secret stores access_key_id and secret_access_key
# as a JSON object, created in 02-mgn/iam.tf.
# --------------------------------------------------------------------------------
echo "NOTE: Fetching agent credentials from Secrets Manager..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${SECRET_NAME}" \
  --region "${AWS_REGION}" \
  --query SecretString \
  --output text)

ACCESS_KEY_ID=$(echo "${SECRET_JSON}" | jq -r '.access_key_id')
SECRET_ACCESS_KEY=$(echo "${SECRET_JSON}" | jq -r '.secret_access_key')

if [[ -z "${ACCESS_KEY_ID}" || -z "${SECRET_ACCESS_KEY}" ]]; then
  echo "ERROR: Failed to parse credentials from secret '${SECRET_NAME}'." >&2
  exit 1
fi

echo "NOTE: Credentials retrieved for key ID: ${ACCESS_KEY_ID}"

# --------------------------------------------------------------------------------
# Wait for SSH availability
# cloud-init may still be running if 02-mgn finished quickly after 01-azure.
# --------------------------------------------------------------------------------
echo "NOTE: Waiting for SSH to become available on ${FQDN}..."
MAX_ATTEMPTS=20
ATTEMPT=0
until ssh -o StrictHostKeyChecking=accept-new \
          -o ConnectTimeout=10 \
          -o BatchMode=yes \
          -i "${PEM_FILE}" \
          "${SSH_USER}@${FQDN}" "true" 2>/dev/null; do
  ATTEMPT=$(( ATTEMPT + 1 ))
  if [[ "${ATTEMPT}" -ge "${MAX_ATTEMPTS}" ]]; then
    echo "ERROR: SSH did not become available after ${MAX_ATTEMPTS} attempts." >&2
    exit 1
  fi
  echo "NOTE: SSH not ready yet, retrying in 15s (attempt ${ATTEMPT}/${MAX_ATTEMPTS})..."
  sleep 15
done

echo "NOTE: SSH is ready. Downloading MGN agent installer..."

# --------------------------------------------------------------------------------
# Download the MGN agent installer onto the source VM
# Fetched directly from the AWS S3 endpoint into /root on the remote machine.
# --------------------------------------------------------------------------------
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=10"

# shellcheck disable=SC2086
ssh ${SSH_OPTS} -i "${PEM_FILE}" "${SSH_USER}@${FQDN}" \
    "sudo wget -q -O /root/aws-replication-installer-init https://aws-application-migration-service-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/latest/linux/aws-replication-installer-init"

echo "NOTE: Running MGN agent installer..."

# --------------------------------------------------------------------------------
# Install the MGN agent on the source VM
# PYTHONUNBUFFERED=1 forces all output to flush immediately so nothing is lost.
# --------------------------------------------------------------------------------
ssh -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=10 \
    -i "${PEM_FILE}" "${SSH_USER}@${FQDN}" \
    "sudo chmod +x /root/aws-replication-installer-init && \
     sudo PYTHONUNBUFFERED=1 /root/aws-replication-installer-init \
       --region ${AWS_REGION} \
       --aws-access-key-id ${ACCESS_KEY_ID} \
       --aws-secret-access-key ${SECRET_ACCESS_KEY} \
       --no-prompt"

echo "NOTE: MGN agent installation complete."
