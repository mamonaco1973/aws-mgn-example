#!/bin/bash
set -euo pipefail

# ================================================================================
# check_env.sh
#
# Validates the local environment before any Terraform phase is applied.
# Checks that required CLI tools are installed and AWS credentials are valid.
# ================================================================================

# --------------------------------------------------------------------------------
# CLI Tool Check
# aws and terraform must be on PATH for either phase to succeed.
# --------------------------------------------------------------------------------
echo "NOTE: Validating that required commands are found in your PATH."

commands=("aws" "terraform" "jq")
all_found=true

for cmd in "${commands[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is not found in the current PATH."
    all_found=false
  else
    echo "NOTE: $cmd is found in the current PATH."
  fi
done

if [ "$all_found" = false ]; then
  echo "ERROR: One or more commands are missing."
  exit 1
fi

echo "NOTE: All required commands are available."

# --------------------------------------------------------------------------------
# AWS Authentication Check
# STS GetCallerIdentity confirms credentials and region are configured.
# Both phases require valid AWS credentials — us-east-2 (source) and
# us-east-1 (MGN target) must be accessible from the same credential set.
# --------------------------------------------------------------------------------
echo "NOTE: Checking AWS CLI connection..."

if ! aws sts get-caller-identity --query "Account" --output text > /dev/null; then
  echo "ERROR: Failed to connect to AWS. Check your credentials and environment variables."
  exit 1
fi

echo "NOTE: Successfully connected to AWS."
