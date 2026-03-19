#!/bin/bash

# ------------------------------------------------------------------------------
# VM bootstrap script (EC2 user-data)
# - Installs Apache (httpd) web server
# - Enables and starts the service
# - Sets a custom landing page to confirm workload identity post-migration
#
# Amazon Linux 2 uses yum and httpd. Its kernel is maintained by AWS and
# tested against the MGN agent — no kernel compatibility issues.
# ------------------------------------------------------------------------------

yum update -y
yum install -y httpd

systemctl enable httpd
systemctl start httpd

# Landing page text changes after cutover — makes migration success obvious.
echo "Welcome to Apache - Source VM in us-east-2" > /var/www/html/index.html
