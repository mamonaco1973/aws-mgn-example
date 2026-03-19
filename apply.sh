#!/bin/bash
set -euo pipefail

# ================================================================================
# apply.sh
#
# Deploys both Terraform phases in order:
#   Phase 1 — 01-azure  : Azure source VM and networking
#   Phase 2 — 02-mgn    : AWS VPC, IAM roles, and MGN initialization
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
# Phase 1 — Azure source environment
# --------------------------------------------------------------------------------
echo "NOTE: Deploying 01-azure..."
terraform -chdir="${SCRIPT_DIR}/01-azure" init
terraform -chdir="${SCRIPT_DIR}/01-azure" apply -auto-approve

# --------------------------------------------------------------------------------
# Phase 2 — AWS MGN target environment
# Must run after Phase 1 so the Azure VM exists before the agent is installed.
# --------------------------------------------------------------------------------
echo "NOTE: Deploying 02-mgn..."
terraform -chdir="${SCRIPT_DIR}/02-mgn" init
terraform -chdir="${SCRIPT_DIR}/02-mgn" apply -auto-approve

# --------------------------------------------------------------------------------
# Phase 3 — MGN agent installation on Azure source VM
# Fetches credentials from Secrets Manager and runs the installer via SSH.
# --------------------------------------------------------------------------------
# echo "NOTE: Installing MGN agent on Azure source VM..."
# "${SCRIPT_DIR}/install_agent.sh"

# echo "NOTE: Deployment complete. The MGN agent is registered and replicating."
