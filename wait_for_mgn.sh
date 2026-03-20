#!/bin/bash
set -euo pipefail

# ================================================================================
# wait_for_mgn.sh
#
# Polls MGN until all expected source servers reach READY_FOR_TEST state.
# Run after both Terraform phases have been applied and source VMs are booting.
#
# Usage: ./wait_for_mgn.sh
# ================================================================================

MGN_REGION="us-east-1"
EXPECTED_SERVERS=1        # Update when adding more source servers
POLL_INTERVAL=30          # Seconds between MGN status checks
MAX_WAIT=7200             # Timeout in seconds (2 hours — initial sync can be slow)

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

echo "NOTE: MGN is ready. Proceed with test launch or cutover."
