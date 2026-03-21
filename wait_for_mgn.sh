#!/bin/bash
set -euo pipefail

# ================================================================================
# wait_for_mgn.sh
#
# Polls MGN until all expected source servers reach READY_FOR_TEST state,
# then launches a test instance for each one. Safe to run multiple times —
# test instances are only launched for servers still in READY_FOR_TEST state.
# Servers already in TESTING, READY_FOR_CUTOVER, or beyond are skipped.
#
# Usage: ./wait_for_mgn.sh
# ================================================================================

MGN_REGION="us-east-1"
EXPECTED_SERVERS=2        # Update when adding more source servers
POLL_INTERVAL=60          # Seconds between MGN status checks
MAX_WAIT=7200             # Timeout in seconds (2 hours — initial sync can be slow)

# --------------------------------------------------------------------------------
# Wait for all expected servers to reach READY_FOR_TEST
# --------------------------------------------------------------------------------
echo "NOTE: Waiting for ${EXPECTED_SERVERS} MGN source server(s) to reach READY_FOR_TEST..."

ELAPSED=0
while true; do

  TOTAL=$(aws mgn describe-source-servers \
    --region "${MGN_REGION}" \
    --filters isArchived=false \
    --query 'length(items)' \
    --output text 2>/dev/null || echo 0)

  READY=$(aws mgn describe-source-servers \
    --region "${MGN_REGION}" \
    --filters isArchived=false \
    --query "length(items[?lifeCycle.state=='READY_FOR_TEST'])" \
    --output text 2>/dev/null || echo 0)

  echo "NOTE: Registered: ${TOTAL}/${EXPECTED_SERVERS} — Ready for test: ${READY}/${EXPECTED_SERVERS} (${ELAPSED}s elapsed)"

  if [[ "${TOTAL}" -ge "${EXPECTED_SERVERS}" && "${READY}" -ge "${EXPECTED_SERVERS}" ]]; then
    echo "NOTE: All ${EXPECTED_SERVERS} source server(s) are READY_FOR_TEST."
    break
  fi

  if [[ "${ELAPSED}" -ge "${MAX_WAIT}" ]]; then
    echo "ERROR: Timed out after ${MAX_WAIT}s waiting for MGN source servers to become ready."
    exit 1
  fi

  sleep "${POLL_INTERVAL}"
  ELAPSED=$(( ELAPSED + POLL_INTERVAL ))

done

# --------------------------------------------------------------------------------
# Fix EC2 Launch Templates — Enable Public IP
# MGN generates per-server EC2 launch templates with AssociatePublicIpAddress
# false, overriding the subnet's map_public_ip_on_launch setting. Patch each
# template before launch so test instances are reachable for validation.
# --------------------------------------------------------------------------------
echo "NOTE: Enabling public IP on EC2 launch templates for all source servers..."

ALL_SERVER_IDS=$(aws mgn describe-source-servers \
  --region "${MGN_REGION}" \
  --filters isArchived=false \
  --query 'items[*].sourceServerID' \
  --output text 2>/dev/null || true)

for SERVER_ID in ${ALL_SERVER_IDS}; do
  LT_ID=$(aws mgn get-launch-configuration \
    --region "${MGN_REGION}" \
    --source-server-id "${SERVER_ID}" \
    --query 'ec2LaunchTemplateID' \
    --output text 2>/dev/null || true)

  if [[ -n "${LT_ID}" && "${LT_ID}" != "None" ]]; then
    NEW_VERSION=$(aws ec2 create-launch-template-version \
      --region "${MGN_REGION}" \
      --launch-template-id "${LT_ID}" \
      --source-version '$Latest' \
      --launch-template-data '{"NetworkInterfaces":[{"DeviceIndex":0,"AssociatePublicIpAddress":true,"DeleteOnTermination":true}]}' \
      --query 'LaunchTemplateVersion.VersionNumber' \
      --output text)
    aws ec2 modify-launch-template \
      --region "${MGN_REGION}" \
      --launch-template-id "${LT_ID}" \
      --default-version "${NEW_VERSION}"
    echo "NOTE: Enabled public IP on ${LT_ID} for ${SERVER_ID}."
  fi
done

# --------------------------------------------------------------------------------
# Launch Test Instances
# Only servers in READY_FOR_TEST state get a test launch. Servers already
# in TESTING or beyond are skipped — prevents duplicate test instances.
# --------------------------------------------------------------------------------
echo "NOTE: Checking which source servers need a test instance launched..."

SERVERS_TO_TEST=$(aws mgn describe-source-servers \
  --region "${MGN_REGION}" \
  --filters isArchived=false \
  --query "items[?lifeCycle.state=='READY_FOR_TEST'].sourceServerID" \
  --output text 2>/dev/null || true)

if [[ -z "${SERVERS_TO_TEST}" ]]; then
  echo "NOTE: No servers in READY_FOR_TEST state — test instances already launched."
else
  for SERVER_ID in ${SERVERS_TO_TEST}; do
    echo "NOTE: Launching test instance for source server ${SERVER_ID}..."
    aws mgn start-test \
      --region "${MGN_REGION}" \
      --source-server-ids "${SERVER_ID}"
    echo "NOTE: Test instance launched for ${SERVER_ID}."
  done
fi

# --------------------------------------------------------------------------------
# Wait for MGN to Provision Test Instance IDs
# MGN takes time to create the AMI and launch instances after start-test.
# Poll until all expected instance IDs appear in the MGN lifecycle record.
# --------------------------------------------------------------------------------
echo "NOTE: Waiting for MGN to provision test instances..."

WAIT_ELAPSED=0
MAX_WAIT_LAUNCH=1800  # 30 min — AMI creation + conversion can be slow

while true; do
  INSTANCE_IDS=$(aws mgn describe-source-servers \
    --region "${MGN_REGION}" \
    --filters isArchived=false \
    --query 'items[*].lifeCycle.lastTest.launchedEc2InstanceID' \
    --output text 2>/dev/null \
    | tr '\t' '\n' | grep '^i-' | sort -u || true)

  ID_COUNT=$(echo "${INSTANCE_IDS}" | grep -c '^i-' 2>/dev/null || echo 0)
  echo "NOTE: Test instances provisioned: ${ID_COUNT}/${EXPECTED_SERVERS} (${WAIT_ELAPSED}s elapsed)"

  if [[ "${ID_COUNT}" -ge "${EXPECTED_SERVERS}" ]]; then
    echo "NOTE: All test instances launched."
    break
  fi

  if [[ "${WAIT_ELAPSED}" -ge "${MAX_WAIT_LAUNCH}" ]]; then
    echo "ERROR: Timed out waiting for MGN to launch test instances."
    exit 1
  fi

  sleep "${POLL_INTERVAL}"
  WAIT_ELAPSED=$(( WAIT_ELAPSED + POLL_INTERVAL ))
done

# --------------------------------------------------------------------------------
# Wait for Test Instances to Reach Running State
# Polls EC2 state for each instance. Exits immediately if an instance
# terminates — no point waiting further if the launch has already failed.
# --------------------------------------------------------------------------------
echo "NOTE: Waiting for test instances to reach running state..."

RUNNING_ELAPSED=0
MAX_WAIT_RUNNING=1200  # 20 min

for INSTANCE_ID in ${INSTANCE_IDS}; do
  while true; do
    STATE=$(aws ec2 describe-instances \
      --region "${MGN_REGION}" \
      --instance-ids "${INSTANCE_ID}" \
      --query 'Reservations[0].Instances[0].State.Name' \
      --output text 2>/dev/null || echo "unknown")

    echo "NOTE: ${INSTANCE_ID} — ${STATE}"

    if [[ "${STATE}" == "running" ]]; then
      break
    fi

    if [[ "${STATE}" == "terminated" || "${STATE}" == "shutting-down" ]]; then
      echo "ERROR: ${INSTANCE_ID} is ${STATE} — check MGN console for details."
      exit 1
    fi

    if [[ "${RUNNING_ELAPSED}" -ge "${MAX_WAIT_RUNNING}" ]]; then
      echo "ERROR: Timed out waiting for ${INSTANCE_ID} to reach running state."
      exit 1
    fi

    sleep "${POLL_INTERVAL}"
    RUNNING_ELAPSED=$(( RUNNING_ELAPSED + POLL_INTERVAL ))
  done
done

# --------------------------------------------------------------------------------
# Wait for HTTP on Port 80
# Confirms the web server is up and the workload is healthy — the strongest
# signal that the migration succeeded and the instance is fully operational.
# --------------------------------------------------------------------------------
echo "NOTE: Waiting for HTTP on port 80 for all test instances..."

MAX_WAIT_HTTP=1200  # 20 min — Windows boot + IIS startup can be slow

for INSTANCE_ID in ${INSTANCE_IDS}; do
  PUBLIC_IP=$(aws ec2 describe-instances \
    --region "${MGN_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || true)

  if [[ -z "${PUBLIC_IP}" || "${PUBLIC_IP}" == "None" ]]; then
    echo "NOTE: ${INSTANCE_ID} has no public IP — skipping HTTP check."
    continue
  fi

  HTTP_ELAPSED=0
  while true; do
    RESPONSE=$(curl -s --max-time 5 "http://${PUBLIC_IP}" 2>/dev/null | tr -d '\r' || true)

    if [[ -n "${RESPONSE}" ]]; then
      echo "NOTE: HTTP OK — ${INSTANCE_ID} (${PUBLIC_IP})"
      echo "${RESPONSE}" | head -1 | sed 's/^/  /'
      break
    fi

    if [[ "${HTTP_ELAPSED}" -ge "${MAX_WAIT_HTTP}" ]]; then
      echo "WARNING: Timed out waiting for HTTP on ${INSTANCE_ID} (${PUBLIC_IP})"
      break
    fi

    echo "NOTE: Waiting for HTTP on ${INSTANCE_ID} (${PUBLIC_IP})... (${HTTP_ELAPSED}s)"
    sleep "${POLL_INTERVAL}"
    HTTP_ELAPSED=$(( HTTP_ELAPSED + POLL_INTERVAL ))
  done
done

echo "NOTE: Done."
