#!/bin/bash
set -euo pipefail

LOG=/root/userdata.log
mkdir -p /root
touch "$LOG"
chmod 600 "$LOG"
exec > >(tee -a "$LOG" | logger -t user-data -s 2>/dev/console) 2>&1
trap 'echo "ERROR at line $LINENO"; exit 1' ERR

echo "user-data start: $(date -Is)"

MGN_REGION="us-east-1"
SECRET_NAME="mgn-agent-credentials"

# ================================================================================
# Network Readiness
# Poll until DNS and HTTPS are available — user-data runs early and network
# may not be ready immediately.
# ================================================================================

for i in {1..60}; do
  echo "checking network..."
  if getent hosts awscli.amazonaws.com >/dev/null 2>&1 && \
     curl -fsS --max-time 5 https://awscli.amazonaws.com/ >/dev/null 2>&1; then
    echo "network ready after $((i*5))s"
    break
  fi
  sleep 5
done

# ================================================================================
# Apache Install
# ================================================================================

yum update -y
yum install -y httpd jq

systemctl enable httpd
systemctl start httpd

# Landing page text changes after cutover — makes migration success obvious.
echo "Welcome to Apache :: Source VM in us-east-2" > /var/www/html/index.html

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
# PYTHONUNBUFFERED=1 ensures all installer output flushes into the log.
# --------------------------------------------------------------------------------

echo "MGN: Running replication agent installer..."

PYTHONUNBUFFERED=1 /root/aws-replication-installer-init \
  --region "${MGN_REGION}" \
  --aws-access-key-id "${ACCESS_KEY_ID}" \
  --aws-secret-access-key "${SECRET_ACCESS_KEY}" \
  --no-prompt 2>&1

echo "user-data complete: $(date -Is)"
