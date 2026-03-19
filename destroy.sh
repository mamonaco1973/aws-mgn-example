#!/bin/bash
set -euo pipefail

# ================================================================================
# destroy.sh
#
# Tears down both Terraform phases in reverse order:
#   Phase 2 — 02-mgn    : AWS resources destroyed first (MGN, IAM, VPC)
#   Phase 1 — 01-azure  : Azure source VM and networking destroyed second
#
# Reverse order is required because Phase 2 outputs may be referenced by
# resources created after Phase 1 (e.g., agent credentials in Secrets Manager).
# ================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------------
# Phase 2 — AWS MGN target environment
# Destroy AWS side first to cleanly remove IAM roles and the Secrets Manager
# secret before tearing down the source VM.
# --------------------------------------------------------------------------------
echo "NOTE: Destroying 02-mgn..."
terraform -chdir="${SCRIPT_DIR}/02-mgn" init
terraform -chdir="${SCRIPT_DIR}/02-mgn" destroy -auto-approve

# --------------------------------------------------------------------------------
# Phase 1 — Azure source environment
# --------------------------------------------------------------------------------
echo "NOTE: Destroying 01-azure..."
terraform -chdir="${SCRIPT_DIR}/01-azure" init
terraform -chdir="${SCRIPT_DIR}/01-azure" destroy -auto-approve

echo "NOTE: Teardown complete."
