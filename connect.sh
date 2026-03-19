#!/bin/bash
set -euo pipefail

# ================================================================================
# connect.sh
#
# SSH into the Azure source VM using the FQDN from Terraform state and the
# generated PEM key. Run from the repo root after 01-azure has been applied.
# ================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AZURE_DIR="${SCRIPT_DIR}/01-azure"
PEM_FILE="${SCRIPT_DIR}/mgn-vm.pem"

# --------------------------------------------------------------------------------
# Resolve FQDN from Terraform output
# --------------------------------------------------------------------------------
echo "Reading VM FQDN from Terraform state..."
FQDN=$(terraform -chdir="${AZURE_DIR}" output -raw vm_public_fqdn)

if [[ -z "${FQDN}" ]]; then
  echo "Error: could not retrieve vm_public_fqdn from Terraform output." >&2
  exit 1
fi

if [[ ! -f "${PEM_FILE}" ]]; then
  echo "Error: PEM key not found at ${PEM_FILE}" >&2
  exit 1
fi

# --------------------------------------------------------------------------------
# Connect
# --------------------------------------------------------------------------------
echo "Connecting to ${FQDN}..."
ssh -o StrictHostKeyChecking=accept-new -i "${PEM_FILE}" "ubuntu@${FQDN}"
