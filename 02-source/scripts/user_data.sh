#!/bin/bash

# ------------------------------------------------------------------------------
# VM bootstrap script (EC2 user-data)
# - Installs Apache (httpd) web server
# - Enables and starts the service
# - Sets a custom landing page to confirm workload identity post-migration
# - Reads MGN agent credentials from Secrets Manager via instance profile
# - Downloads and installs the MGN replication agent
#
# Amazon Linux 2 uses yum and httpd. Its kernel is maintained by AWS and
# tested against the MGN agent — no kernel compatibility issues.
# All output is captured in /var/log/cloud-init-output.log.
# ------------------------------------------------------------------------------

MGN_REGION="us-east-1"
SECRET_NAME="mgn-agent-credentials"

# ================================================================================
# Apache Install
# ================================================================================

yum update -y
yum install -y httpd jq

systemctl enable httpd
systemctl start httpd

# Landing page text changes after cutover — makes migration success obvious.
echo "Welcome to Apache - Source VM in us-east-2" > /var/www/html/index.html

# ================================================================================
# MGN Agent Installation
#
# Reads agent credentials from Secrets Manager using the EC2 instance profile
# (no hardcoded keys). Downloads the MGN replication agent installer from the
# AWS S3 endpoint and registers this server with the MGN service in us-east-1.
# ================================================================================

echo "MGN: Fetching agent credentials from Secrets Manager..."

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${SECRET_NAME}" \
  --region "${MGN_REGION}" \
  --query SecretString \
  --output text)

ACCESS_KEY_ID=$(echo "${SECRET_JSON}"     | jq -r '.access_key_id')
SECRET_ACCESS_KEY=$(echo "${SECRET_JSON}" | jq -r '.secret_access_key')

if [[ -z "${ACCESS_KEY_ID}" || -z "${SECRET_ACCESS_KEY}" ]]; then
  echo "MGN: ERROR — failed to parse credentials from secret '${SECRET_NAME}'."
  exit 1
fi

echo "MGN: Credentials retrieved for key ID: ${ACCESS_KEY_ID}"

# --------------------------------------------------------------------------------
# Download MGN installer
# --------------------------------------------------------------------------------

echo "MGN: Downloading replication agent installer..."

wget -q -O /root/aws-replication-installer-init \
  "https://aws-application-migration-service-${MGN_REGION}.s3.${MGN_REGION}.amazonaws.com/latest/linux/aws-replication-installer-init"

chmod +x /root/aws-replication-installer-init

# --------------------------------------------------------------------------------
# Run MGN installer
# PYTHONUNBUFFERED=1 ensures all output flushes to cloud-init-output.log.
# --------------------------------------------------------------------------------

echo "MGN: Running replication agent installer..."

PYTHONUNBUFFERED=1 /root/aws-replication-installer-init \
  --region "${MGN_REGION}" \
  --aws-access-key-id "${ACCESS_KEY_ID}" \
  --aws-secret-access-key "${SECRET_ACCESS_KEY}" \
  --no-prompt 2>&1

echo "MGN: Agent installation complete. Exit: $?"
