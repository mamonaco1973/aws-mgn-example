#!/bin/bash
set -euo pipefail

# ================================================================================
# revert.sh
#
# Reverts all MGN source servers from TESTING back to READY_FOR_TEST.
# Uses change-server-life-cycle-state to flip the MGN lifecycle state, then
# terminates the EC2 test instances directly via EC2 API.
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
# Collect test instance IDs before changing state so we can terminate them.
# MGN tags all instances it launches with AWSApplicationMigrationServiceManaged=true,
# which is more reliable than tracing through job records.
# --------------------------------------------------------------------------------
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "${MGN_REGION}" \
  --filters \
    "Name=tag:AWSApplicationMigrationServiceManaged,Values=mgn.amazonaws.com" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text 2>/dev/null | tr '\t' '\n' | grep '^i-' | sort -u || true)

if [[ -n "${INSTANCE_IDS}" ]]; then
  echo "NOTE: Test instances to be terminated: $(echo "${INSTANCE_IDS}" | tr '\n' ' ')"
fi

# --------------------------------------------------------------------------------
# Flip MGN lifecycle state back to READY_FOR_TEST.
# change-server-life-cycle-state updates the MGN state directly without
# requiring an active EC2 instance, unlike terminate-target-instances.
# --------------------------------------------------------------------------------
echo "NOTE: Reverting MGN lifecycle state to READY_FOR_TEST..."

for SERVER_ID in ${TESTING_SERVER_IDS}; do
  echo "NOTE: Reverting ${SERVER_ID}..."
  aws mgn change-server-life-cycle-state \
    --region "${MGN_REGION}" \
    --source-server-id "${SERVER_ID}" \
    --life-cycle state=READY_FOR_TEST
  echo "NOTE: Reverted ${SERVER_ID}."
done

# --------------------------------------------------------------------------------
# Terminate EC2 test instances directly.
# change-server-life-cycle-state only updates MGN state — it does not
# terminate the running EC2 instances. Terminate them via EC2 API so they
# do not continue running as orphans.
# --------------------------------------------------------------------------------
if [[ -z "${INSTANCE_IDS}" ]]; then
  echo "NOTE: No test instance IDs found — skipping EC2 termination."
else
  echo "NOTE: Terminating test instances..."
  # shellcheck disable=SC2086
  aws ec2 terminate-instances \
    --region "${MGN_REGION}" \
    --instance-ids ${INSTANCE_IDS} > /dev/null
  echo "NOTE: Termination requested for: $(echo "${INSTANCE_IDS}" | tr '\n' ' ')"

  # --------------------------------------------------------------------------------
  # Wait for test instances to reach terminated state
  # --------------------------------------------------------------------------------
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
