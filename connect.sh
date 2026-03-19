#!/bin/bash
set -euo pipefail

# ================================================================================
# connect.sh
#
# SSH into the Azure source VM using the FQDN from Terraform state and the
# generated PEM key. Run from the repo root after 01-azure has been applied.
# ================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEM_FILE="${SCRIPT_DIR}/mgn-vm.pem"

# --------------------------------------------------------------------------------
# Resolve FQDN from Terraform output
# Reads directly from state so the hostname is always current.
# --------------------------------------------------------------------------------
echo "Reading VM FQDN from Terraform state..."
FQDN=$(terraform -chdir="${SCRIPT_DIR}/01-azure" output -raw vm_public_fqdn)

if [[ -z "${FQDN}" ]]; then
  echo "ERROR: could not retrieve vm_public_fqdn from Terraform output." >&2
  exit 1
fi

if [[ ! -f "${PEM_FILE}" ]]; then
  echo "ERROR: PEM key not found at ${PEM_FILE}" >&2
  exit 1
fi

# --------------------------------------------------------------------------------
# Connect
# accept-new accepts the host key on first connection without prompting.
# --------------------------------------------------------------------------------
echo "Connecting to ${FQDN}..."
ssh -o StrictHostKeyChecking=accept-new -i "${PEM_FILE}" "ubuntu@${FQDN}"
