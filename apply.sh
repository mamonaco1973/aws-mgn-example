#!/bin/bash
set -euo pipefail

# ================================================================================
# apply.sh
#
# Deploys both Terraform phases in order:
#   Phase 1 — 01-source  : EC2 source VM in us-east-2 and networking
#   Phase 2 — 02-mgn  : AWS VPC, IAM roles, and MGN initialization in us-east-1
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
# Phase 1 — AWS source environment (us-east-2)
# --------------------------------------------------------------------------------
echo "NOTE: Deploying 01-source..."
terraform -chdir="${SCRIPT_DIR}/01-source" init
terraform -chdir="${SCRIPT_DIR}/01-source" apply -auto-approve

# --------------------------------------------------------------------------------
# Phase 2 — AWS MGN target environment (us-east-1)
# Must run after Phase 1 so the source VM exists before the agent is installed.
# --------------------------------------------------------------------------------
echo "NOTE: Deploying 02-mgn..."
terraform -chdir="${SCRIPT_DIR}/02-mgn" init
terraform -chdir="${SCRIPT_DIR}/02-mgn" apply -auto-approve

# --------------------------------------------------------------------------------
# Phase 3 — MGN agent installation on source VM
# Fetches credentials from Secrets Manager and runs the installer via SSH.
# --------------------------------------------------------------------------------
# echo "NOTE: Installing MGN agent on source VM..."
# "${SCRIPT_DIR}/install_agent.sh"

# echo "NOTE: Deployment complete. The MGN agent is registered and replicating."
