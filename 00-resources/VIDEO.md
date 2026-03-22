#AWS #MGN #ApplicationMigrationService #Terraform #CloudMigration #LiftAndShift #EC2

*AWS Application Migration Service (MGN) – End-to-End Migration Example*

In this video, we build a fully automated server migration demo using AWS Application Migration Service (MGN) — Amazon's agent-based block-level replication service for lifting and shifting servers between AWS regions.

Two EC2 source instances in us-east-2 — an Amazon Linux 2 server running Apache and a Windows Server 2019 server running IIS — are continuously replicated to us-east-1 using MGN's block-level replication engine. The entire environment is provisioned with Terraform and driven end-to-end by shell scripts, from agent installation through test launch and validation.

This project mirrors how MGN is used in real migrations: a landing zone is prepared first, agents register and begin syncing, test instances validate the workload in the target region, and live source changes are replicated continuously without downtime.

What You'll Learn
- Understand the MGN migration lifecycle: NOT_READY → READY_FOR_TEST → TESTING → CUTOVER
- Structure a two-phase Terraform deployment that sequences landing zone before source
- Install MGN replication agents automatically at boot using EC2 user-data
- Store and retrieve MGN agent credentials securely from AWS Secrets Manager
- Configure MGN replication templates with PUBLIC_IP routing for cross-region replication
- Create IAM service roles under the /service-role/ path required for MGN PassRole
- Launch and validate test instances in the target region before cutting over
- Automate MGN lifecycle management entirely with AWS CLI shell scripts
- Tear down all MGN-managed resources (servers, jobs, replication servers) in the correct order before destroying Terraform infrastructure

Resources Deployed
- MGN replication and launch templates (us-east-1)
- VPC 10.50.0.0/16 with public and MGN staging subnets (us-east-1)
- VPC 10.1.0.0/16 with public subnet and internet gateway (us-east-2)
- Amazon Linux 2 EC2 instance running Apache (us-east-2 source)
- Windows Server 2019 EC2 instance running IIS (us-east-2 source)
- IAM service roles for replication, conversion, and launched instances
- IAM user mgn-agent-user with agent installation policy
- AWS Secrets Manager secret storing MGN agent credentials
- EC2 test instances launched by MGN in us-east-1


GitHub
https://github.com/mamonaco1973/aws-mgn-example

README
https://github.com/mamonaco1973/aws-mgn-example/blob/main/README.md

Timestamps

00:00 Introduction
00:22 Architecture 
01:15 Build the Code
01:32 Build Results
02:10 Demo
