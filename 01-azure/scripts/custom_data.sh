#!/bin/bash

# ------------------------------------------------------------------------------
# Basic custom data script
# - Installs Apache
# - Enables and starts the service
# - Sets a custom default index page
# ------------------------------------------------------------------------------

sudo apt update -y
sudo apt install apache2 isc-dhcp-client -y

sudo systemctl enable apache2
sudo systemctl start apache2

# ------------------------------------------------------------------------------
# Create custom Apache landing page
# ------------------------------------------------------------------------------

echo "Welcome to Apache - Deployed in Azure" | sudo tee /var/www/html/index.html

cd /root
sudo wget -O ./aws-replication-installer-init https://aws-application-migration-service-us-east-1.s3.us-east-1.amazonaws.com/latest/linux/aws-replication-installer-init

