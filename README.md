# AWS Application Migration Service (MGN) Demo

This project delivers a fully automated demonstration of **AWS Application
Migration Service (MGN)** — Amazon's agent-based block-level replication
service for lifting and shifting servers between AWS regions.

It uses **Terraform** and **shell scripts** to provision both the source
environment (us-east-2) and the MGN target environment (us-east-1), install
MGN agents automatically via EC2 user-data, and drive the full migration
lifecycle through test launch and cutover.

Key capabilities demonstrated:

1. **Cross-Region Server Migration** — Replicates live EC2 instances from
   us-east-2 to us-east-1 using MGN's continuous block-level replication,
   with no downtime during sync.
2. **Heterogeneous Source Fleet** — Migrates both an Amazon Linux 2 instance
   running Apache and a Windows Server 2019 instance running IIS in the same
   migration wave.
3. **Fully Automated Agent Installation** — MGN replication agents are
   installed automatically at boot via EC2 user-data scripts, with credentials
   pulled securely from AWS Secrets Manager using the instance's IAM profile.
4. **Infrastructure as Code** — Two-phase Terraform deployment provisions the
   MGN target environment first (VPC, IAM, replication templates), then the
   source environment (VPCs, EC2 instances) — mirroring real-world sequencing
   where the landing zone is prepared before agents connect.
5. **Migration Lifecycle Automation** — Shell scripts handle the full MGN
   lifecycle: waiting for replication readiness, launching test instances,
   validating workloads via HTTP, and tearing down all resources in the correct
   dependency order.

Together, these components form a **self-contained, end-to-end migration
demo** that exercises the complete MGN workflow — from initial agent
registration through test launch and cutover validation.

## Architecture



## MGN Migration Lifecycle

| Stage | Description |
|---|---|
| `NOT_READY` | Agent installed; initial sync in progress |
| `READY_FOR_TEST` | Full sync complete; test launch available |
| `TESTING` | Test instance running in us-east-1 |
| `READY_FOR_CUTOVER` | Test complete; production cutover available |
| `CUTOVER` | Production instance running in us-east-1 |

## Two-Phase Terraform Deployment

| Phase | Directory | Region | Purpose |
|---|---|---|---|
| 1 | `01-mgn/` | us-east-1 | VPC, IAM roles, MGN replication and launch templates |
| 2 | `02-source/` | us-east-2 | Source VPC, EC2 instances, IAM instance profile |

Phase 1 must complete before Phase 2 so MGN templates and IAM roles exist
when the agents connect.

## Prerequisites

* [An AWS Account](https://aws.amazon.com/console/)
* [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
* [Install Terraform](https://developer.hashicorp.com/terraform/install)
* [Install jq](https://jqlang.github.io/jq/download/)

If this is your first time following along, we recommend starting with this
video:
**[AWS + Terraform: Easy Setup](https://www.youtube.com/watch?v=9clW3VQLyxA)**
— it walks through configuring your AWS credentials, Terraform backend, and
CLI environment.

## Download this Repository

```bash
git clone https://github.com/mamonaco1973/aws-mgn-example.git
cd aws-mgn-example
```

## Build the Code

Run [check_env.sh](check_env.sh) to validate your environment, then run
[apply.sh](apply.sh) to provision all infrastructure and wait for MGN
replication to complete.

```bash
~/aws-mgn-example$ ./apply.sh
NOTE: Running environment validation...
NOTE: aws is found in the current PATH.
NOTE: terraform is found in the current PATH.
NOTE: jq is found in the current PATH.
NOTE: All required commands are available.
NOTE: Successfully logged into AWS.
NOTE: Deploying 01-mgn...
NOTE: Deploying 02-source...
NOTE: Waiting for 2 MGN source server(s) to reach READY_FOR_TEST...
NOTE: Registered: 2/2 — Ready for test: 0/2 (0s elapsed)
...
NOTE: All 2 source server(s) are READY_FOR_TEST.
NOTE: Launching test instance for source server s-xxxxxxxxxx...
NOTE: Launching test instance for source server s-yyyyyyyyyy...
```

`apply.sh` blocks until both source servers complete initial replication
(typically 30–60 minutes) and automatically launches a test instance for each.

### Build Results

When the deployment completes, the following resources are created:

- **MGN Target Environment (us-east-1):**
  - VPC `10.50.0.0/16` with public subnet and dedicated MGN staging subnet
  - Security group with TCP 1500 inbound open — required for MGN block-level
    replication traffic from cross-region source agents
  - IAM service roles for replication servers, conversion servers, and
    launched instances — all under the `/service-role/` path required for MGN's
    service-linked role PassRole permission
  - IAM user `mgn-agent-user` with
    `AWSApplicationMigrationAgentInstallationPolicy`; access key stored in
    Secrets Manager as `mgn-agent-credentials`
  - MGN replication template configured with `PUBLIC_IP` data plane routing
    — required for cross-region replication without a VPN or Direct Connect
  - MGN launch template targeting the us-east-1 VPC and subnet

- **Source Environment (us-east-2):**
  - VPC `10.1.0.0/16` with public subnet and internet gateway
  - **Amazon Linux 2** EC2 instance (`t3.medium`) running Apache; user-data
    installs the MGN Linux replication agent automatically at boot
  - **Windows Server 2019** EC2 instance (`t3.medium`) running IIS; user-data
    installs AWS CLI, IIS, and the MGN Windows replication agent automatically
    at boot
  - IAM instance profile granting SSM Session Manager access and scoped
    Secrets Manager read — used by user-data to retrieve agent credentials
    without embedding keys in the image

- **Automation Scripts:**
  - [`apply.sh`](apply.sh) — deploys both Terraform phases, then blocks on
    MGN replication readiness before launching test instances
  - [`destroy.sh`](destroy.sh) — cleanly tears down all resources in reverse
    dependency order: disconnects and deletes MGN source servers, deletes MGN
    jobs, terminates replication and conversion servers, removes the MGN
    conversion security group, then destroys both Terraform phases
  - [`wait_for_mgn.sh`](wait_for_mgn.sh) — polls MGN until all expected source
    servers reach `READY_FOR_TEST`, then launches a test instance for each
    (idempotent — skips servers already in `TESTING` or beyond)
  - [`validate.sh`](validate.sh) — curls the HTTP workload on all source and
    target servers; source IPs come from Terraform state, target IPs are
    resolved from MGN's launched instance records
  - [`modify.sh`](modify.sh) — uses AWS SSM Run Command to update the landing
    page on both source servers, appending a timestamp; demonstrates that
    MGN replication is continuous and target instances reflect source changes
    after the next sync cycle

## Validate the Migration

After test instances are running, validate that workloads are accessible on
both source and target:

```bash
~/aws-mgn-example$ ./validate.sh

======================================================================
Source Servers (us-east-2)
======================================================================
  Linux (Amazon Linux 2) (1.2.3.4):

    Welcome to Apache
    Source VM in us-east-2

  Windows Server 2019 (5.6.7.8):

    Welcome to IIS
    Windows Server 2019 Source VM in us-east-2

======================================================================
Target Servers (us-east-1)
======================================================================
  Target (i-xxxxxxxxxx) (9.10.11.12):

    Welcome to Apache
    Source VM in us-east-2
```

## Modify Source Workloads

Use [`modify.sh`](modify.sh) to update the landing pages on both source servers
via SSM. This demonstrates that MGN continuously replicates changes from source
to target — re-running `validate.sh` after a sync cycle will show the updated
content on target instances as well.

```bash
~/aws-mgn-example$ ./modify.sh

======================================================================
Modify Source Servers — us-east-2
Timestamp: 2026-03-20T16:29:28Z
======================================================================

Linux (Amazon Linux 2)
----------------------------------------------------------------------
  Sending command to Linux (i-xxxxxxxxxx)...
  Command ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  Status: Success
    Page updated.

Windows (Server 2019)
----------------------------------------------------------------------
  Sending command to Windows (i-yyyyyyyyyy)...
  Command ID: yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
  Status: Success
    Page updated.

Done. Run ./validate.sh to confirm the changes are live.
```

After running `modify.sh`, validate output will show:

```
    Welcome to Apache
    Source VM in us-east-2
    UPDATED 2026-03-20T16:29:28Z
```

## Destroy

```bash
~/aws-mgn-example$ ./destroy.sh
NOTE: Cleaning up MGN source servers in us-east-1...
NOTE: Disconnecting source server s-xxxxxxxxxx...
NOTE: Archiving source server s-xxxxxxxxxx...
NOTE: Deleting source server s-xxxxxxxxxx...
NOTE: Deleting MGN jobs in us-east-1...
NOTE: Terminating MGN replication servers in us-east-1...
NOTE: Terminating MGN conversion servers in us-east-1...
NOTE: Deleting MGN conversion server security group in us-east-1...
NOTE: Destroying 01-mgn...
NOTE: Destroying 02-source...
NOTE: Teardown complete.
```

`destroy.sh` must clean up MGN-managed resources (source servers, jobs,
replication servers, conversion servers, and the auto-created conversion
security group) before Terraform can destroy the VPC — these resources are
created by MGN outside of Terraform and will block VPC deletion if left behind.
