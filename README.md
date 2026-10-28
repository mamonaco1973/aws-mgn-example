# AWS Application Migration Service (MGN): Cross-Region Lift and Shift

An end-to-end demo of **AWS Application Migration Service (MGN)**, AWS's
agent-based, block-level replication service for rehosting servers. Two
source servers in **us-east-2**, an Amazon Linux 2023 web server and a
Windows Server 2022 IIS server, install the MGN agent at boot and replicate
continuously to **us-east-1**, where the scripts launch test instances from
them and check that the same web pages come up.

| Piece | Where | Role |
|---|---|---|
| **mgn-source** (Linux) | us-east-2, `mgn-source-subnet` | Amazon Linux 2023, `t3.medium`; Apache; user data installs the MGN Linux agent |
| **Windows source** | us-east-2, `mgn-source-subnet` | Windows Server 2022, `t3.medium`; IIS; user data installs the AWS CLI, IIS and the MGN Windows agent |
| **Source VPC** | us-east-2, `10.1.0.0/16` | one public subnet (`10.1.1.0/24`); SSH, RDP and HTTP open; instance role with SSM and read access to the agent secret |
| **MGN service** | us-east-1 | initialized by `scripts/init_mgn.sh`, which replaces any existing replication and launch configuration templates |
| **Replication template** | us-east-1 | dedicated `t3.medium` replication servers in `mgn-staging-subnet`, `PUBLIC_IP` data plane routing with a public IP, GP3 staging disks, default EBS encryption, no bandwidth limit |
| **Launch template** | us-east-1 | launch started, copy tags, don't copy private IPs, basic right-sizing; `wait_for_mgn.sh` points each server's EC2 launch template at `mgn-public-subnet` with a public IP |
| **MGN VPC** | us-east-1, `10.50.0.0/16` | `mgn-public-subnet` (`10.50.1.0/24`) and `mgn-staging-subnet` (`10.50.2.0/24`), both routed to the internet gateway; `mgn-target-sg` opens 22, 3389, 80 and 1500 |
| **IAM** | global | the MGN service roles (`AWSApplicationMigrationReplicationServerRole`, `…ConversionServerRole`, `…MGHRole`, `…LaunchInstanceWithDrsRole`, `…LaunchInstanceWithSsmRole`, `…AgentRole`) and the `mgn-agent-user` user with `AWSApplicationMigrationAgentInstallationPolicy` |
| **mgn-agent-credentials** | Secrets Manager, us-east-1 | the agent user's access key |

## Architecture

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="architecture-dark.svg">
  <img alt="An Amazon Linux 2023 server running Apache and a Windows Server 2022 server running IIS in us-east-2 read an IAM access key from Secrets Manager in us-east-1 at boot and install the AWS MGN replication agent, which registers with Application Migration Service in us-east-1. MGN launches a replication server in the staging subnet, and the agents stream block-level changes to it over TCP port 1500 on its public IP. When both servers are ready for testing, wait_for_mgn.sh points each server's launch template at the public subnet and starts a test launch, which converts the replicated disks into test instances with public IPs. modify.sh changes the source web pages through SSM Run Command to show that replication is continuous." src="architecture-light.svg">
</picture>

Regenerate with `python3 make_diagram.py`.

- **`01-mgn/`** (us-east-1): the MGN VPC and security group, the IAM roles,
  the agent user and its secret, and `scripts/init_mgn.sh`, which Terraform
  runs to initialize MGN and create the templates.
- **`02-source/`** (us-east-2): the source VPC, both instances and their
  user data, the instance role, and an SSH key pair (written to
  `mgn-vm.pem` in the repository root).
- **`wait_for_mgn.sh`**, **`validate.sh`**, **`modify.sh`**,
  **`revert.sh`**: the migration lifecycle (below).

The landing zone comes first: the MGN templates and roles have to exist
before the agents connect.

## The migration lifecycle

| State | Meaning |
|---|---|
| `NOT_READY` | agent installed; initial sync in progress |
| `READY_FOR_TEST` | initial sync complete; a test launch is available |
| `TESTING` | a test instance is running in us-east-1 |
| `READY_FOR_CUTOVER` | testing finished; cutover is available |
| `CUTOVER` | the production instance is running in us-east-1 |

The scripts take the servers as far as `TESTING`:

- **`wait_for_mgn.sh`** polls every 30 seconds, up to two hours, until two
  source servers are registered and `READY_FOR_TEST`. It then patches each
  server's EC2 launch template with `mgn-public-subnet`, `mgn-target-sg` and
  a public IP, and runs `start-test` for every server still in
  `READY_FOR_TEST`, so it's safe to run again.
- **`validate.sh`** curls each source server (IPs from Terraform state) and
  each MGN-launched instance in us-east-1.
- **`modify.sh`** rewrites both source pages through SSM Run Command,
  adding `UPDATED <timestamp>`.
- **`revert.sh`** terminates the test instances and moves the servers in
  `TESTING` back to `READY_FOR_TEST`, so `wait_for_mgn.sh` can launch fresh
  ones from the latest replicated data.

## Prerequisites

* [An AWS Account](https://aws.amazon.com/console/)
* [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
* [Install Terraform](https://developer.hashicorp.com/terraform/install)
* [Install jq](https://jqlang.github.io/jq/download/)

If this is your first time watching our content, we recommend starting with
this video: [AWS + Terraform: Easy Setup](https://www.youtube.com/watch?v=9clW3VQLyxA).

## Deploy

```bash
git clone https://github.com/mamonaco1973/aws-mgn-example.git
cd aws-mgn-example
./apply.sh
```

`apply.sh` runs `check_env.sh`, applies `01-mgn` and `02-source`, runs
`wait_for_mgn.sh` (initial replication usually takes 30 to 60 minutes),
then `validate.sh`:

```
======================================================================
Source Servers (us-east-2)
======================================================================
  Linux (Amazon Linux 2023) (1.2.3.4):

    Welcome to Apache
    Source VM in us-east-2

  Windows Server 2022 (5.6.7.8):

    Welcome to IIS
    Windows Server 2022 Source VM in us-east-2

======================================================================
Target Servers (us-east-1)
======================================================================
  Target (i-xxxxxxxxxx) (9.10.11.12):

    Welcome to Apache
    Source VM in us-east-2
```

## Try it

1. Change the source pages:

   ```bash
   ./modify.sh
   ```

2. The test instances were launched from the earlier data, so they still
   show the old pages. Launch new ones from the latest replicated data:

   ```bash
   ./revert.sh
   ./wait_for_mgn.sh
   ./validate.sh
   ```

   The targets now show the update too:

   ```
       Welcome to Apache
       Source VM in us-east-2
       UPDATED 2026-03-20T16:29:28Z
   ```

3. Connect to a source server with SSM, or with SSH as `ec2-user` and
   `mgn-vm.pem`, and look at the agent's progress in the MGN console under
   **Source servers**.

## Teardown

```bash
./destroy.sh
```

MGN creates resources outside Terraform that block deleting the VPC, so
`destroy.sh` first disconnects, archives and deletes the source servers,
terminates the MGN-launched instances (test, replication and conversion
servers), deletes the MGN jobs and the conversion security group, and only
then destroys `02-source` and `01-mgn`.

## Notes

- **Lab only.** SSH, RDP and HTTP are open to `0.0.0.0/0` on the source
  servers and on `mgn-target-sg`, and so is the replication port 1500.
- The agents authenticate with a long-lived IAM user access key, read from
  Secrets Manager at boot.
- The Windows user data also creates a local Administrators account named
  after the agent user, with the **secret access key as its password**
  (labelled as a debug account).
- `init_mgn.sh` deletes any existing MGN replication and launch templates in
  us-east-1 before creating its own, which would affect other MGN work in
  the same account and region.
