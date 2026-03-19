#!/bin/bash
set -euo pipefail

# ================================================================================
# check_env.sh
#
# Validates the local environment before any Terraform phase is applied.
# Checks that required CLI tools are installed, Azure ARM environment
# variables are set, and both cloud CLIs can authenticate successfully.
# ================================================================================

# --------------------------------------------------------------------------------
# CLI Tool Check
# az, aws, and terraform must all be on PATH for either phase to succeed.
# --------------------------------------------------------------------------------
echo "NOTE: Validating that required commands are found in your PATH."

commands=("az" "aws" "terraform")
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
# Azure Environment Variable Check
# AzureRM provider reads these variables directly; they must be exported
# before running Terraform or the provider will fail to authenticate.
# --------------------------------------------------------------------------------
echo "NOTE: Validating that required environment variables are set."

required_vars=("ARM_CLIENT_ID" "ARM_CLIENT_SECRET" "ARM_SUBSCRIPTION_ID" "ARM_TENANT_ID")
all_set=true

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "ERROR: $var is not set or is empty."
    all_set=false
  else
    echo "NOTE: $var is set."
  fi
done

if [ "$all_set" = false ]; then
  echo "ERROR: One or more required environment variables are missing or empty."
  exit 1
fi

echo "NOTE: All required environment variables are set."

# --------------------------------------------------------------------------------
# Azure Login
# Authenticates the az CLI using the service principal so subsequent az
# commands and the AzureRM provider share the same identity.
# --------------------------------------------------------------------------------
echo "NOTE: Logging in to Azure using Service Principal..."

if ! az login --service-principal \
     --username "$ARM_CLIENT_ID" \
     --password "$ARM_CLIENT_SECRET" \
     --tenant "$ARM_TENANT_ID" > /dev/null 2>&1; then
  echo "ERROR: Failed to log into Azure. Check your credentials and environment variables."
  exit 1
fi

echo "NOTE: Successfully logged into Azure."

# --------------------------------------------------------------------------------
# AWS Authentication Check
# STS GetCallerIdentity confirms credentials and region are configured.
# No output is needed — a non-zero exit code is the only signal required.
# --------------------------------------------------------------------------------
echo "NOTE: Checking AWS CLI connection..."

if ! aws sts get-caller-identity --query "Account" --output text > /dev/null; then
  echo "ERROR: Failed to connect to AWS. Check your credentials and environment variables."
  exit 1
fi

echo "NOTE: Successfully logged into AWS."
