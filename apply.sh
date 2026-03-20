#!/bin/bash
set -euo pipefail

# ================================================================================
# apply.sh
#
# Deploys both Terraform phases in order:
#   Phase 1 — 01-mgn    : AWS VPC, IAM roles, and MGN initialization in us-east-1
#   Phase 2 — 02-source : EC2 source VM in us-east-2 (agent installs via user-data)
#
# After both phases, polls MGN until all expected source servers reach
# READY_FOR_TEST state before exiting.
#
# Prerequisites: run check_env.sh (called automatically below) to confirm
# all CLI tools and credentials are in place before provisioning begins.
# ================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------------
# Environment validation
# Abort early if tools or credentials are missing to avoid a partial deploy.
# --------------------------------------------------------------------------------
"${SCRIPT_DIR}/check_env.sh"

# --------------------------------------------------------------------------------
# Phase 1 — AWS MGN target environment (us-east-1)
# --------------------------------------------------------------------------------
echo "NOTE: Deploying 01-mgn..."
terraform -chdir="${SCRIPT_DIR}/01-mgn" init
terraform -chdir="${SCRIPT_DIR}/01-mgn" apply -auto-approve

# --------------------------------------------------------------------------------
# Phase 2 — AWS source environment (us-east-2)
# Agent installs automatically via user-data on first boot.
# --------------------------------------------------------------------------------
echo "NOTE: Deploying 02-source..."
terraform -chdir="${SCRIPT_DIR}/02-source" init
terraform -chdir="${SCRIPT_DIR}/02-source" apply -auto-approve

echo "NOTE: Infrastructure complete. "

# --------------------------------------------------------------------------------
# Phase 3 - Wait for servers to register for replication
# --------------------------------------------------------------------------------

echo "NOTE: Waiting for replication to complete."
./wait_for_mgn.sh
