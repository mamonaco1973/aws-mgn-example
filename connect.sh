#!/bin/bash
set -euo pipefail

# ================================================================================
# connect.sh
#
# SSH into the source EC2 instance using the public DNS from Terraform state
# and the generated PEM key. Run from the repo root after 02-source has been
# applied.
# ================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEM_FILE="${SCRIPT_DIR}/mgn-vm.pem"

# --------------------------------------------------------------------------------
# Resolve public DNS from Terraform output
# Reads directly from state so the hostname is always current.
# --------------------------------------------------------------------------------
echo "Reading VM public DNS from Terraform state..."
HOST=$(terraform -chdir="${SCRIPT_DIR}/02-source" output -raw vm_public_dns)

if [[ -z "${HOST}" ]]; then
  echo "ERROR: could not retrieve vm_public_dns from Terraform output." >&2
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
echo "Connecting to ${HOST}..."
ssh -o StrictHostKeyChecking=accept-new -i "${PEM_FILE}" "ec2-user@${HOST}"
