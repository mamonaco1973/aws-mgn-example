# CLAUDE.md — aws-mgn-example

## Project Overview

This project demonstrates VM migration using **AWS Application Migration Service
(MGN)**. Two EC2 source instances in **us-east-2** (Amazon Linux 2 + Windows
Server 2019) are replicated to **us-east-1** via block-level replication. Using
same-cloud cross-region migration keeps the demo self-contained and avoids the
OS kernel compatibility issues present in cross-cloud migrations.

## Project Structure

```
aws-mgn-example/
├── 01-mgn/                    # Phase 1: MGN target environment (us-east-1)
│   ├── scripts/
│   │   └── init_mgn.sh        # Idempotent MGN init: deletes and recreates
│   │                          #   replication and launch templates via AWS CLI
│   ├── iam.tf                 # IAM roles for replication/conversion/launch
│   │                          #   (all under /service-role/ path — required
│   │                          #   for MGN service-linked role PassRole)
│   │                          # IAM user mgn-agent-user + Secrets Manager
│   ├── main.tf                # AWS provider
│   ├── mgn.tf                 # Security group (SSH/HTTP/TCP 1500 inbound),
│   │                          #   null_resource runs init_mgn.sh via local-exec
│   ├── network.tf             # VPC 10.50.0.0/16, public + staging subnets
│   ├── outputs.tf             # VPC ID, subnet IDs
│   └── variables.tf
├── 02-source/                 # Phase 2: EC2 source environment (us-east-2)
│   ├── scripts/
│   │   ├── user_data.sh       # Amazon Linux 2: installs httpd + MGN agent
│   │   └── user_data.ps1      # Windows Server 2019: installs IIS + MGN agent
│   ├── iam.tf                 # EC2 instance profile:
│   │                          #   AmazonSSMManagedInstanceCore
│   │                          #   secretsmanager:GetSecretValue (scoped)
│   ├── linux.tf               # Amazon Linux 2 EC2 (t3.medium), AMI lookup,
│   │                          #   outputs: vm_public_ip, vm_instance_id
│   ├── main.tf                # AWS provider, SSH key pair, key file output
│   ├── network.tf             # VPC 10.1.0.0/16, subnet, IGW, security group
│   ├── variables.tf
│   └── windows.tf             # Windows Server 2019 EC2 (t3.medium), separate
│                              #   security group (RDP + HTTP),
│                              #   outputs: windows_public_ip, windows_instance_id
├── apply.sh                   # Deploy 01-mgn then 02-source, then block on
│                              #   wait_for_mgn.sh
├── aws-mgn-demo.drawio        # Architecture diagram (draw.io)
├── check_env.sh               # Validate CLI tools and AWS credentials
├── connect.sh                 # SSH into the Linux source instance
├── destroy.sh                 # Full teardown in reverse dependency order
├── modify.sh                  # SSM Run Command: updates landing pages on
│                              #   both source servers with a timestamp
├── validate.sh                # curl HTTP on source and target servers;
│                              #   splits response on " :: " for display
└── wait_for_mgn.sh            # Poll MGN until READY_FOR_TEST, then launch
                               #   test instances (idempotent)
```

## Deployment Workflow

### Prerequisites

- `terraform` >= 1.5.0
- `aws` CLI configured with credentials for both us-east-2 and us-east-1
- `jq`

### Deploy

```bash
./check_env.sh   # Validate tools and AWS credentials
./apply.sh       # Deploy 01-mgn, then 02-source, then wait for MGN readiness
```

### Destroy

```bash
./destroy.sh     # Full cleanup — see destroy order below
```

## Phase Details

### Phase 1 — MGN Target Environment (`01-mgn/`) — us-east-1

- VPC `10.50.0.0/16`, public subnet `10.50.1.0/24`, staging subnet `10.50.2.0/24`
- Security group with **TCP 1500 inbound** — required for cross-region MGN
  block-level replication from source agents
- IAM roles with `path = "/service-role/"` — critical for the MGN
  service-linked role's PassRole permission. All four roles:
  `AWSApplicationMigrationReplicationServerRole`,
  `AWSApplicationMigrationConversionServerRole`,
  `AWSApplicationMigrationLaunchInstanceWithDrsRole`,
  `AWSApplicationMigrationLaunchInstanceWithSsmRole`
- IAM user `mgn-agent-user` with `AWSApplicationMigrationAgentInstallationPolicy`
  (not `AWSApplicationMigrationAgentPolicy` — wrong policy, causes exit 19)
- Agent credentials stored in Secrets Manager as `mgn-agent-credentials`
- `init_mgn.sh` is **idempotent**: deletes existing replication and launch
  templates before recreating them — prevents stale subnet/config issues
  after VPC recreation
- Replication template uses `dataPlaneRouting=PUBLIC_IP` — required for
  cross-region replication without VPN/Direct Connect (PRIVATE_IP causes
  exit 247 — agents cannot reach staging subnet private IPs across regions)

### Phase 2 — Source Environment (`02-source/`) — us-east-2

- VPC `10.1.0.0/16`, single public subnet, internet gateway
- **Amazon Linux 2** (`t3.medium`) — MGN agent installed via `user_data.sh`
  at boot. Uses AWS-maintained kernel — no kernel compilation issues.
  Landing page: `"Welcome to Apache :: Source VM in us-east-2"`
- **Windows Server 2019** (`t3.medium`) — MGN agent installed via
  `user_data.ps1` at boot (AWS CLI installed first, then IIS, then agent).
  Landing page: `"Welcome to IIS :: Windows Server 2019 Source VM in us-east-2"`
- EC2 instance profile provides SSM + scoped Secrets Manager read so
  user-data can retrieve agent credentials without embedded keys
- RSA 4096 SSH key written to `../mgn-vm.pem` (gitignored)

## Script Details

### `apply.sh`
Deploys `01-mgn` then `02-source` with `terraform init` + `apply -auto-approve`,
then calls `wait_for_mgn.sh`.

### `wait_for_mgn.sh`
Polls `aws mgn describe-source-servers` every 30s (2-hour timeout) until
`EXPECTED_SERVERS=2` reach `READY_FOR_TEST`, then calls `aws mgn start-test`
for each. Idempotent — skips servers already in `TESTING` or beyond.

### `validate.sh`
- Source IPs from `terraform -chdir=02-source output -raw`
- Target IPs from MGN lifecycle (`lastTest.launchedEc2InstanceID` and
  `lastCutover.launchedEc2InstanceID`), deduplicated with `sort -u`
- Response split on ` :: ` via `awk gsub` so each segment prints on its
  own line (e.g. `"A :: B :: C"` → three lines)

### `modify.sh`
Uses `aws ssm send-command` to update landing pages on both source servers.
Builds `--parameters` JSON via `jq -n --arg` to safely encode shell commands
containing `$` and quotes. Writes the full page string directly (no read-back)
to avoid cumulative UPDATED appends. Format:
`"Welcome to Apache :: Source VM in us-east-2 :: UPDATED <timestamp>"`

### `destroy.sh`
Cleanup order (each step required before the next or Terraform will fail):
1. Disconnect, archive, delete all MGN source servers
2. Delete all MGN jobs
3. Terminate replication servers (by Name tag)
4. Wait for replication servers to terminate
5. Terminate conversion servers (by Name tag)
6. Wait for conversion servers to terminate
7. Delete MGN conversion server security group (auto-created by MGN, not
   managed by Terraform)
8. `terraform destroy 01-mgn`
9. `terraform destroy 02-source`

## Key IAM Resources

| Resource | Purpose |
|---|---|
| `AWSApplicationMigrationReplicationServerRole` | MGN replication servers — must be `/service-role/` path |
| `AWSApplicationMigrationConversionServerRole` | MGN conversion servers — must be `/service-role/` path |
| `AWSApplicationMigrationLaunchInstanceWithSsmRole` | SSM on launched instances — must be `/service-role/` path |
| `AWSApplicationMigrationLaunchInstanceWithDrsRole` | DRS launch — must be `/service-role/` path |
| `mgn-agent-user` | Agent IAM user; key in Secrets Manager `mgn-agent-credentials` |
| `mgn-source-instance-role` | EC2 instance profile on source VMs (SSM + Secrets Manager read) |

## Terraform Providers

| Provider | Version |
|---|---|
| `hashicorp/aws` | ~> 6.0 |
| `hashicorp/tls` | SSH key generation |
| `hashicorp/local` | Writing key file to disk |
| `hashicorp/null` | local-exec for `init_mgn.sh` |

## Important Notes

- **Do not use `filebase64()`** for `user_data` — Terraform's `user_data`
  attribute takes plaintext; use `file()`.
- **MGN service-linked role** (`AWSServiceRoleForApplicationMigrationService`)
  is created automatically by `aws mgn initialize-service` inside `init_mgn.sh`.
  Do not manage it with `aws_iam_service_linked_role` in Terraform — it already
  exists after first initialization and Terraform will error on recreation.
- **Windows SSM** takes 7–10 minutes to come online after boot (OS init +
  SSM agent registration). `modify.sh` may need to be retried if run
  immediately after deploy.
- **Local Terraform state only** — no backend configured. Never commit
  `*.tfstate` or `*.tfstate.backup`.
- The `connect.sh` script SSHs into the Linux source instance using
  `../mgn-vm.pem`. Windows access is via SSM Session Manager (no SSH).

## Code Commenting Standards

Claude should apply consistent, professional commenting when modifying code.

### General Rules

- Keep comment lines **≤ 80 characters**
- Do **not change code behavior**
- Preserve existing variable names and structure
- Comments should explain **intent**, not restate obvious code
- Prefer concise, structured comments

### Terraform Files

```hcl
# ================================================================================
# Section Name
# Description of resources created in this block
# ================================================================================
```

Comments should explain **why infrastructure exists**, not repeat the resource
definition.

### Shell Scripts

```bash
# ================================================================================
# Section Name
# Purpose of this block
# ================================================================================

# --------------------------------------------------------------------------------
# Subsection Name
# Brief operational note
# --------------------------------------------------------------------------------
```

- Preserve strict bash style: `set -euo pipefail`
- Keep scripts idempotent where possible
- Explain why a command block exists, not what obvious flags do
