#!/bin/bash
set -euo pipefail

# ================================================================================
# revert.sh
#
# Reverts all MGN source servers from TESTING back to READY_FOR_TEST by
# terminating their test instances. Waits for all EC2 instances to reach
# terminated state before exiting.
#
# Usage: ./revert.sh
# ================================================================================

MGN_REGION="us-east-1"
POLL_INTERVAL=15
MAX_WAIT=600  # 10 min — test instances terminate quickly

# --------------------------------------------------------------------------------
# Find servers currently in TESTING state
# --------------------------------------------------------------------------------
echo "NOTE: Looking for source servers in TESTING state..."

TESTING_SERVER_IDS=$(aws mgn describe-source-servers \
  --region "${MGN_REGION}" \
  --filters isArchived=false \
  --query "items[?lifeCycle.state=='TESTING'].sourceServerID" \
  --output text 2>/dev/null || true)

if [[ -z "${TESTING_SERVER_IDS}" ]]; then
  echo "NOTE: No servers in TESTING state — nothing to revert."
  exit 0
fi

echo "NOTE: Found servers to revert: ${TESTING_SERVER_IDS}"

# --------------------------------------------------------------------------------
# For each TESTING server: check the launchStatus in its last test job and
# the EC2 instance state before attempting termination.
#
# terminate-target-instances fails (ConflictException) when:
#   - launchStatus is IN_PROGRESS  (instance still being converted/launched)
#   - launchStatus is FAILED       (test instance launch failed — nothing to kill)
#   - launchStatus is TERMINATED   (instance was terminated outside of MGN)
#   - a terminate job is already running for this server
#
# Calling terminate per-server rather than in a batch lets us skip stuck
# servers and still revert the healthy ones.
# --------------------------------------------------------------------------------
INSTANCE_IDS=""

for SERVER_ID in ${TESTING_SERVER_IDS}; do

  JOB_ID=$(aws mgn describe-source-servers \
    --region "${MGN_REGION}" \
    --filters isArchived=false \
    --query "items[?sourceServerID=='${SERVER_ID}'].lifeCycle.lastTest.initiated.jobID" \
    --output text 2>/dev/null | tr '\t' '\n' | grep '^mgnjob-' | head -1 || true)

  LAUNCH_STATUS="UNKNOWN"
  INSTANCE_ID=""

  if [[ -n "${JOB_ID}" ]]; then
    LAUNCH_STATUS=$(aws mgn describe-jobs \
      --region "${MGN_REGION}" \
      --filters jobIDs="${JOB_ID}" \
      --query 'items[0].participatingServers[0].launchStatus' \
      --output text 2>/dev/null || true)
    LAUNCH_STATUS="${LAUNCH_STATUS:-UNKNOWN}"

    INSTANCE_ID=$(aws mgn describe-jobs \
      --region "${MGN_REGION}" \
      --filters jobIDs="${JOB_ID}" \
      --query 'items[0].participatingServers[0].launchedEc2InstanceID' \
      --output text 2>/dev/null | grep '^i-' || true)
  fi

  # Verify the EC2 instance is in a terminable state.
  EC2_STATE="not-found"
  if [[ -n "${INSTANCE_ID}" ]]; then
    EC2_STATE=$(aws ec2 describe-instances \
      --region "${MGN_REGION}" \
      --instance-ids "${INSTANCE_ID}" \
      --query 'Reservations[0].Instances[0].State.Name' \
      --output text 2>/dev/null || echo "not-found")
  fi

  echo "NOTE: ${SERVER_ID} — job=${JOB_ID:-none} launchStatus=${LAUNCH_STATUS} instance=${INSTANCE_ID:-none} ec2=${EC2_STATE}"

  # Only call terminate-target-instances when the test instance is LAUNCHED and
  # the EC2 instance exists. Any other combination means MGN has nothing to
  # terminate and will reject the request with ConflictException.
  if [[ "${LAUNCH_STATUS}" == "LAUNCHED" && "${EC2_STATE}" != "terminated" && "${EC2_STATE}" != "not-found" ]]; then
    echo "NOTE: Reverting ${SERVER_ID} to READY_FOR_TEST..."
    if aws mgn terminate-target-instances \
        --region "${MGN_REGION}" \
        --source-server-ids "${SERVER_ID}" > /dev/null 2>&1; then
      echo "NOTE: Revert initiated for ${SERVER_ID}."
      [[ -n "${INSTANCE_ID}" ]] && INSTANCE_IDS=$(printf '%s\n%s' "${INSTANCE_IDS}" "${INSTANCE_ID}")
    else
      echo "WARNING: terminate-target-instances failed for ${SERVER_ID} — check MGN console."
    fi
  else
    echo "WARNING: ${SERVER_ID} cannot be reverted via terminate-target-instances."
    echo "         launchStatus=${LAUNCH_STATUS} ec2=${EC2_STATE}"
    echo "         If FAILED or TERMINATED: the test instance may have crashed or been"
    echo "         terminated outside MGN. Disconnect and reconnect the MGN agent to"
    echo "         reset the server back to READY_FOR_TEST."
  fi

done

INSTANCE_IDS=$(echo "${INSTANCE_IDS}" | grep '^i-' | sort -u || true)

# --------------------------------------------------------------------------------
# Wait for test instances to reach terminated state
# --------------------------------------------------------------------------------
if [[ -z "${INSTANCE_IDS}" ]]; then
  echo "NOTE: No instance IDs found — skipping EC2 termination wait."
else
  echo "NOTE: Waiting for test instances to terminate..."

  ELAPSED=0
  while true; do
    ALL_DONE=true
    for INSTANCE_ID in ${INSTANCE_IDS}; do
      STATE=$(aws ec2 describe-instances \
        --region "${MGN_REGION}" \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "terminated")

      echo "NOTE: ${INSTANCE_ID} — ${STATE}"

      if [[ "${STATE}" != "terminated" ]]; then
        ALL_DONE=false
      fi
    done

    if [[ "${ALL_DONE}" == "true" ]]; then
      echo "NOTE: All test instances terminated."
      break
    fi

    if [[ "${ELAPSED}" -ge "${MAX_WAIT}" ]]; then
      echo "ERROR: Timed out waiting for test instances to terminate."
      exit 1
    fi

    sleep "${POLL_INTERVAL}"
    ELAPSED=$(( ELAPSED + POLL_INTERVAL ))
  done
fi

# --------------------------------------------------------------------------------
# Confirm MGN state
# --------------------------------------------------------------------------------
echo "NOTE: Confirming MGN server states..."

aws mgn describe-source-servers \
  --region "${MGN_REGION}" \
  --filters isArchived=false \
  --query 'items[*].{ID:sourceServerID,State:lifeCycle.state}' \
  --output table

echo "NOTE: Revert complete. Run ./wait_for_mgn.sh to launch new test instances."
