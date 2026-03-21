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
# Set Target Instance Type
# update-launch-configuration is per-source-server — the launch template only
# controls right-sizing method, not the actual type. Run for all registered
# servers so the setting is in place before the test launch.
# --------------------------------------------------------------------------------
echo "NOTE: Setting target instance type to t3.medium for all source servers..."

ALL_SERVER_IDS=$(aws mgn describe-source-servers \
  --region "${MGN_REGION}" \
  --filters isArchived=false \
  --query 'items[*].sourceServerID' \
  --output text 2>/dev/null || true)

for SERVER_ID in ${ALL_SERVER_IDS}; do
  echo "NOTE: Setting instance type for ${SERVER_ID}..."
  # update-launch-configuration requires --name even when only changing the
  # instance type — fetch the current value to avoid a BadRequestException.
  SERVER_NAME=$(aws mgn get-launch-configuration \
    --region "${MGN_REGION}" \
    --source-server-id "${SERVER_ID}" \
    --query 'name' \
    --output text 2>/dev/null || true)
  aws mgn update-launch-configuration \
    --region "${MGN_REGION}" \
    --source-server-id "${SERVER_ID}" \
    --name "${SERVER_NAME}" \
    --target-instance-type t3.medium
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

echo "NOTE: Waiting 600 seconds for test servers to start."

sleep 600

echo "NOTE: Done. Monitor test instance progress in the MGN console."
