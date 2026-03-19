# CLAUDE.md — aws-mgn-example

## Project Overview

This project demonstrates VM migration using **AWS Application Migration Service (MGN)**. The source is an EC2 instance in **us-east-2**; the target is **us-east-1**. Using same-cloud cross-region migration keeps the demo self-contained and avoids OS kernel compatibility issues present in cross-cloud migrations.

## Project Structure

```
aws-mgn-example/
├── 01-source/             # Phase 1: EC2 source environment in us-east-2 (Terraform)
│   ├── scripts/
│   │   └── user_data.sh      # VM startup: installs Apache
│   ├── main.tf               # Provider setup, SSH key pair
│   ├── network.tf            # VPC, subnet, IGW, route table, security group
│   ├── vm.tf                 # Ubuntu 24.04 EC2 instance, AMI lookup
│   └── variables.tf          # prefix, aws_region, vpc_cidr, instance_type
├── 02-mgn/             # Phase 2: AWS MGN target environment (Terraform)
│   ├── scripts/
│   │   └── init_mgn.sh       # Initializes MGN service via AWS CLI
│   ├── iam.tf                # IAM roles for MGN replication/conversion/launch
│   ├── main.tf               # AWS provider, AZ data source
│   ├── mgn.tf                # Security group, triggers init_mgn.sh
│   ├── network.tf            # VPC, IGW, public/staging subnets, routes
│   ├── outputs.tf            # VPC ID, subnet IDs, next-step instructions
│   └── variables.tf          # aws_region, vpc_cidr, subnet CIDRs, instance type
├── apply.sh            # Deploy both phases in order
├── check_env.sh        # Validate CLI tools and AWS credentials
├── connect.sh          # SSH into the source EC2 instance
├── install_agent.sh    # Install MGN agent on the source VM (Phase 3)
├── destroy.sh          # Destroy both phases in reverse order
└── .gitignore          # Excludes .terraform/, *.tfstate, *.pem
```

## Deployment Workflow

### Prerequisites

- `terraform` >= 1.5.0
- `aws` (AWS CLI, configured with valid credentials for both us-east-2 and us-east-1)

### Deploy

```bash
./check_env.sh   # Validate tools and AWS credentials
./apply.sh       # Deploy 01-source, then 02-mgn (auto-approves)
```

### Destroy

```bash
./destroy.sh     # Destroys 02-mgn first, then 01-source
```

## Phase Details

### Phase 1 — AWS Source (`01-source/`)

Creates the migration source in us-east-2:
- Ubuntu 24.04 LTS EC2 instance (`t3.micro`)
- VPC `10.1.0.0/16` / subnet `10.1.1.0/24`
- Security group allowing SSH (22) and HTTP (80)
- RSA 4096 SSH key written to `../mgn-vm.pem` (gitignored)
- User-data script installs Apache2

### Phase 2 — AWS MGN (`02-mgn/`)

Creates the migration target in us-east-1:
- VPC `10.50.0.0/16` with Internet Gateway
- Public subnet `10.50.1.0/24` and staging subnet `10.50.2.0/24`
- Security group (SSH + HTTP ingress)
- IAM roles: `AWSApplicationMigrationReplicationServerRole`, `ConversionServerRole`, `MGHRole`, `AgentRole`, etc.
- IAM user `mgn-agent-user` with access key stored in AWS Secrets Manager
- MGN service initialized via `scripts/init_mgn.sh` (replication template + launch template)

## Key IAM Resources

| Resource | Purpose |
|---|---|
| `AWSApplicationMigrationReplicationServerRole` | MGN replication servers |
| `AWSApplicationMigrationConversionServerRole` | MGN conversion servers |
| `AWSApplicationMigrationAgentRole` | Source-side MGN agent auth |
| `AWSApplicationMigrationLaunchInstanceWithSsmRole` | SSM access on launched instances |
| `mgn-agent-user` (IAM user) | Agent credentials; key stored in Secrets Manager |

## Terraform Providers

| Provider | Version |
|---|---|
| `hashicorp/aws` | ~> 6.0 |
| `hashicorp/tls` | for SSH key generation |
| `hashicorp/local` | for writing key files |
| `hashicorp/null` | for local-exec provisioner |

## Notes

- `mgn-vm.pem` is generated at the repo root and gitignored — required for SSH to the source VM.
- `init_mgn.sh` uses `aws mgn` CLI calls; it must run after IAM roles are created (enforced via Terraform `depends_on`).
- No Terraform backend is configured — state is local. Do not commit `*.tfstate` files.
- Phase 3 (`install_agent.sh`) is commented out in `apply.sh` — uncomment to automate agent install.

## Code Commenting Standards

Claude should apply consistent, professional commenting when modifying
code.

### General Rules

-   Keep comment lines **≤ 80 characters**
-   Do **not change code behavior**
-   Preserve existing variable names and structure
-   Comments should explain **intent**, not restate obvious code
-   Prefer concise, structured comments

### Python Files

Modules should begin with a structured header:

```python
# ================================================================================
# Module Name
#
# Purpose
# Brief explanation of what this module does.
#
# Key Responsibilities
# - Responsibility 1
# - Responsibility 2
# ================================================================================
```

Functions should include a short structured description:

```python
# --------------------------------------------------------------------------------
# Function: function_name
#
# Purpose
# Explain what the function does.
#
# Arguments
# - arg_name : description
#
# Returns
# - description
# --------------------------------------------------------------------------------
```

### Terraform Files

Use section banners to describe infrastructure blocks:

```hcl
# ================================================================================
# Section Name
# Description of resources created in this block
# ================================================================================
```

Comments should explain **why infrastructure exists**, not repeat the
resource definition.

### JavaScript Files

- Keep comment lines <= 80 characters
- Do not change UI behavior unless explicitly asked
- Preserve existing function names, IDs, and DOM structure
- Prefer concise section banners for major areas
- Use comments to explain intent, data flow, and UI behavior
- Do not add noisy comments for obvious one-line DOM operations
- Keep comments professional and compact
- Prefer small, reviewable diffs

Use section banners like:

```javascript
/* ================================================================================ */
/* Section Name */
/* Purpose of this section */
/* ================================================================================ */
```

For functions, use short block comments when helpful:

```javascript
/* -------------------------------------------------------------------------------- */
/* Function: functionName                                                            */
/* Purpose: Explain what this function does                                         */
/* -------------------------------------------------------------------------------- */
```

### Shell Scripts

- Keep comment lines <= 80 characters
- Preserve strict bash style: set -euo pipefail
- Use your quick start comment style
- Prefer bannered sections for each major operation
- Explain why a command block exists, not what obvious flags do
- Keep comments concise and operational
- Do not rewrite working command structure unless explicitly asked
- Preserve variable names unless a rename is necessary
- Prefer readable step-by-step execution flow
- Keep scripts idempotent where possible

Scripts should use section banners like:

```bash
# ================================================================================
# Section Name
# Purpose of this block
# ================================================================================
```

For smaller subsections:

```bash
# --------------------------------------------------------------------------------
# Subsection Name
# Brief operational note
# --------------------------------------------------------------------------------
```


  

