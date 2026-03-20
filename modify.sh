#!/bin/bash
set -euo pipefail

# ================================================================================
# modify.sh
#
# Uses SSM Run Command to update the landing page on both source servers.
# Appends " UPDATED - <timestamp>" to the existing page content so the
# change is visible in curl output before and after migration.
#
# Usage: ./modify.sh
# ================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REGION="us-east-2"

# --------------------------------------------------------------------------------
# ssm_run <label> <instance_id> <document> <command>
# Encodes <command> as JSON via jq to avoid shell quoting issues, sends the
# SSM Run Command, waits for completion, and prints the output.
# --------------------------------------------------------------------------------
ssm_run() {
  local LABEL="$1"
  local INSTANCE_ID="$2"
  local DOCUMENT="$3"
  local COMMAND="$4"

  echo "  Sending command to ${LABEL} (${INSTANCE_ID})..."

  # Use jq to safely encode the command string — avoids $, ", and space issues
  # that break --parameters shorthand syntax.
  local PARAMS
  PARAMS=$(jq -n --arg cmd "$COMMAND" '{"commands": [$cmd]}')

  local COMMAND_ID
  COMMAND_ID=$(aws ssm send-command \
    --region "${SOURCE_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --document-name "${DOCUMENT}" \
    --parameters "${PARAMS}" \
    --query 'Command.CommandId' \
    --output text)

  echo "  Command ID: ${COMMAND_ID}"
  echo "  Waiting for completion..."

  aws ssm wait command-executed \
    --region "${SOURCE_REGION}" \
    --command-id "${COMMAND_ID}" \
    --instance-id "${INSTANCE_ID}" 2>/dev/null || true

  local STATUS OUTPUT STDERR
  STATUS=$(aws ssm get-command-invocation \
    --region "${SOURCE_REGION}" \
    --command-id "${COMMAND_ID}" \
    --instance-id "${INSTANCE_ID}" \
    --query 'Status' \
    --output text)

  OUTPUT=$(aws ssm get-command-invocation \
    --region "${SOURCE_REGION}" \
    --command-id "${COMMAND_ID}" \
    --instance-id "${INSTANCE_ID}" \
    --query 'StandardOutputContent' \
    --output text 2>/dev/null || true)

  STDERR=$(aws ssm get-command-invocation \
    --region "${SOURCE_REGION}" \
    --command-id "${COMMAND_ID}" \
    --instance-id "${INSTANCE_ID}" \
    --query 'StandardErrorContent' \
    --output text 2>/dev/null || true)

  echo "  Status: ${STATUS}"
  if [[ -n "${OUTPUT}" && "${OUTPUT}" != "None" ]]; then
    echo "${OUTPUT}" | sed 's/^/    /'
  fi
  if [[ -n "${STDERR}" && "${STDERR}" != "None" ]]; then
    echo "  STDERR:"
    echo "${STDERR}" | sed 's/^/    /'
  fi
  echo ""
}

# --------------------------------------------------------------------------------
# Resolve instance IDs from Terraform state
# --------------------------------------------------------------------------------
LINUX_ID=$(terraform -chdir="${SCRIPT_DIR}/02-source" output -raw vm_instance_id 2>/dev/null || true)
WINDOWS_ID=$(terraform -chdir="${SCRIPT_DIR}/02-source" output -raw windows_instance_id 2>/dev/null || true)

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

echo ""
echo "======================================================================"
echo "Modify Source Servers — ${SOURCE_REGION}"
echo "Timestamp: ${TIMESTAMP}"
echo "======================================================================"
echo ""

# --------------------------------------------------------------------------------
# Linux — AWS-RunShellScript
# Read the current page, append the UPDATED marker, write it back.
# --------------------------------------------------------------------------------
echo "Linux (Amazon Linux 2)"
echo "----------------------------------------------------------------------"

if [[ -z "${LINUX_ID}" || "${LINUX_ID}" == "None" ]]; then
  echo "  No Linux instance ID found in Terraform state."
else
  LINUX_CMD='echo "Welcome to Apache :: Source VM in us-east-2 :: UPDATED '"${TIMESTAMP}"'" > /var/www/html/index.html; echo "Page updated."'
  ssm_run "Linux" "${LINUX_ID}" "AWS-RunShellScript" "${LINUX_CMD}"
fi

# --------------------------------------------------------------------------------
# Windows — AWS-RunPowerShellScript
# Read the current page, append the UPDATED marker, write it back to both files.
# --------------------------------------------------------------------------------
echo "Windows (Server 2019)"
echo "----------------------------------------------------------------------"

if [[ -z "${WINDOWS_ID}" || "${WINDOWS_ID}" == "None" ]]; then
  echo "  No Windows instance ID found in Terraform state."
else
  WIN_CMD='$updated = "Welcome to IIS :: Windows Server 2019 Source VM in us-east-2 :: UPDATED '"${TIMESTAMP}"'"; Set-Content -Path "C:\inetpub\wwwroot\iisstart.htm" -Value $updated; Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $updated; Write-Output "Page updated."'
  ssm_run "Windows" "${WINDOWS_ID}" "AWS-RunPowerShellScript" "${WIN_CMD}"
fi

echo "Done. Run ./validate.sh to confirm the changes are live."
echo ""
