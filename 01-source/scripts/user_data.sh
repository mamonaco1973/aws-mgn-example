#!/bin/bash

# ------------------------------------------------------------------------------
# VM bootstrap script (EC2 user-data)
# - Installs Apache web server
# - Enables and starts the service
# - Sets a custom landing page to confirm workload identity post-migration
#
# No kernel swap needed — Canonical EC2 images ship linux-aws which is fully
# supported by AWS MGN out of the box.
# ------------------------------------------------------------------------------

apt update -y
apt install -y apache2

systemctl enable apache2
systemctl start apache2

# Landing page text changes after cutover — makes migration success obvious.
echo "Welcome to Apache - Source VM in us-east-2" > /var/www/html/index.html
