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
# Collect test instance IDs before termination so we can wait on them.
# Instance IDs are on the MGN job, not in the lifecycle record.
# --------------------------------------------------------------------------------
JOB_IDS=$(aws mgn describe-source-servers \
  --region "${MGN_REGION}" \
  --filters isArchived=false \
  --query 'items[*].lifeCycle.lastTest.initiated.jobID' \
  --output text 2>/dev/null | tr '\t' '\n' | grep '^mgnjob-' | sort -u || true)

INSTANCE_IDS=""
for JOB_ID in ${JOB_IDS}; do
  IDS=$(aws mgn describe-jobs \
    --region "${MGN_REGION}" \
    --filters jobIDs="${JOB_ID}" \
    --query 'items[*].participatingServers[*].launchedEc2InstanceID' \
    --output text 2>/dev/null | tr '\t' '\n' | grep '^i-' || true)
  INSTANCE_IDS=$(printf '%s\n%s' "${INSTANCE_IDS}" "${IDS}")
done
INSTANCE_IDS=$(echo "${INSTANCE_IDS}" | grep '^i-' | sort -u || true)

if [[ -n "${INSTANCE_IDS}" ]]; then
  echo "NOTE: Test instances to be terminated: $(echo "${INSTANCE_IDS}" | tr '\n' ' ')"
fi

# --------------------------------------------------------------------------------
# Terminate test instances — moves servers back to READY_FOR_TEST
# Pass all IDs in a single call so the API validates all of them atomically;
# calling one-at-a-time causes ConflictException if any server has already
# left TESTING state between the describe query above and this step.
# --------------------------------------------------------------------------------
echo "NOTE: Reverting servers to READY_FOR_TEST..."

# shellcheck disable=SC2086
aws mgn terminate-target-instances \
  --region "${MGN_REGION}" \
  --source-server-ids ${TESTING_SERVER_IDS} > /dev/null

echo "NOTE: Revert initiated for: ${TESTING_SERVER_IDS}"

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
