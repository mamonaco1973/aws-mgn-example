
#!/bin/bash

cd 02-mgn

terraform init
terraform destroy -auto-approve

cd ..

cd 01-azure

terraform init
terraform destroy -auto-approve

cd ..


