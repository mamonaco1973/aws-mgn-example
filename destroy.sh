
#!/bin/bash

cd 01-azure

terraform init
terraform destroy -auto-approve

cd ..
