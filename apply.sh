#!/bin/bash

./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment check failed. Exiting."
  exit 1
fi

cd 01-azure

terraform init
terraform apply -auto-approve

cd ..

# ssh -o StrictHostKeyChecking=accept-new -i mgn-vm.pem \
# ubuntu@mgn-vm-e4dee2.centralus.cloudapp.azure.com


cd 02-mgn

terraform init
terraform apply -auto-approve

cd ..