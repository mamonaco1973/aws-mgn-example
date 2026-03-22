#AWS #MGN #ApplicationMigrationService #Terraform #CloudMigration #LiftAndShift #EC2

*AWS Server Migration – MGN Quick Start*

GitHub

https://github.com/mamonaco1973/aws-mgn-example

README

https://github.com/mamonaco1973/aws-mgn-example/blob/main/README.md

This Quick Start shows you how to lift and shift EC2 instances across AWS regions using AWS Application Migration Service (MGN) and Terraform.

No manual setup.
No console clicking.
Fully automated.
Fully reproducible.

What This Quick Start Deploys

• MGN replication and launch templates in us-east-1
• Two-phase Terraform deployment — landing zone first, source environment second
• Amazon Linux 2 instance running Apache (us-east-2 source)
• Windows Server 2019 instance running IIS (us-east-2 source)
• MGN replication agents installed automatically at boot via EC2 user-data
• Agent credentials stored and retrieved securely from AWS Secrets Manager
• IAM service roles under the /service-role/ path required for MGN PassRole
• Automated test instance launch and HTTP validation in the target region
