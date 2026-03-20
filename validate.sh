#!/bin/bash
set -euo pipefail

# ================================================================================
# validate.sh
#
# Validates the migration by curling the landing page on all source and target
# servers. Source IPs come from Terraform state; target IPs are resolved from
# MGN's record of launched test/cutover instances.
#
# Usage: ./validate.sh
# ================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REGION="us-east-2"
TARGET_REGION="us-east-1"

# --------------------------------------------------------------------------------
# check_http <label> <ip>
# Curls the server and prints the response on one line. Reports clearly on
# failure so the output is easy to scan.
# --------------------------------------------------------------------------------
check_http() {
  local LABEL="$1"
  local IP="$2"
  printf "  %-45s : " "${LABEL} (${IP})"
  RESPONSE=$(curl -s --max-time 10 "http://${IP}" 2>/dev/null || true)
  if [[ -n "${RESPONSE}" ]]; then
    echo "${RESPONSE}"
  else
    echo "FAILED — no response"
  fi
}

# --------------------------------------------------------------------------------
# Source Servers — us-east-2
# IPs read directly from Terraform state.
# --------------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "Source Servers (${SOURCE_REGION})"
echo "======================================================================"

LINUX_IP=$(terraform -chdir="${SCRIPT_DIR}/02-source" output -raw vm_public_ip 2>/dev/null || true)
WINDOWS_IP=$(terraform -chdir="${SCRIPT_DIR}/02-source" output -raw windows_public_ip 2>/dev/null || true)

if [[ -n "${LINUX_IP}" && "${LINUX_IP}" != "None" ]]; then
  check_http "Linux (Amazon Linux 2)" "${LINUX_IP}"
else
  echo "  Linux: no IP found in Terraform state"
fi

if [[ -n "${WINDOWS_IP}" && "${WINDOWS_IP}" != "None" ]]; then
  check_http "Windows Server 2019" "${WINDOWS_IP}"
else
  echo "  Windows: no IP found in Terraform state"
fi

# --------------------------------------------------------------------------------
# Target Servers — us-east-1
# Instance IDs resolved from MGN lifecycle — checks both test launch and
# cutover launch so it works regardless of which stage has been completed.
# --------------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "Target Servers (${TARGET_REGION})"
echo "======================================================================"

LAUNCHED_IDS=$(aws mgn describe-source-servers \
  --region "${TARGET_REGION}" \
  --filters isArchived=false \
  --query 'items[*].[lifeCycle.lastTest.launchedEc2InstanceID,lifeCycle.lastCutover.launchedEc2InstanceID]' \
  --output text 2>/dev/null \
  | tr '\t' '\n' \
  | grep -v '^None$' \
  | grep -v '^$' \
  | sort -u || true)

if [[ -z "${LAUNCHED_IDS}" ]]; then
  echo "  No target instances found. Run a test launch or cutover first."
else
  for INSTANCE_ID in ${LAUNCHED_IDS}; do
    PUBLIC_IP=$(aws ec2 describe-instances \
      --region "${TARGET_REGION}" \
      --instance-ids "${INSTANCE_ID}" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' \
      --output text 2>/dev/null || true)

    if [[ -n "${PUBLIC_IP}" && "${PUBLIC_IP}" != "None" ]]; then
      check_http "Target (${INSTANCE_ID})" "${PUBLIC_IP}"
    else
      echo "  ${INSTANCE_ID}: no public IP — instance may be stopped"
    fi
  done
fi

echo ""
