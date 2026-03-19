# ==============================================================================
# IAM Data Sources
#
# Retrieves the caller's account ID so assume-role policies can scope
# conditions to this specific account, preventing cross-account misuse.
# ==============================================================================

data "aws_caller_identity" "current" {}

# ==============================================================================
# IAM Assume-Role Policies
#
# Shared trust policy documents reused across multiple roles. Keeping them
# as data sources avoids duplicating the JSON inline in each role resource.
# ==============================================================================

# Allows EC2 instances (replication, conversion, launch servers) to assume
# their respective MGN roles via instance profiles.
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Allows the MGN service itself to assume roles on behalf of the account
# (used by MGHRole for Migration Hub progress tracking).
data "aws_iam_policy_document" "mgn_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["mgn.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Scoped trust policy for the agent role. SourceIdentity and SourceAccount
# conditions ensure only agents registered to this account can assume it,
# preventing privilege escalation from other accounts' MGN sources.
data "aws_iam_policy_document" "mgn_agent_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["mgn.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:SetSourceIdentity"
    ]

    # Source identities for MGN agents always start with "s-".
    condition {
      test     = "StringLike"
      variable = "sts:SourceIdentity"
      values   = ["s-*"]
    }

    # Locks role assumption to this AWS account only.
    condition {
      test     = "StringLike"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# ==============================================================================
# AWSApplicationMigrationReplicationServerRole
#
# Attached to EC2 replication servers that MGN launches in the staging
# subnet. Grants permissions to read/write replication data in S3 and
# communicate with the MGN control plane.
# ==============================================================================

resource "aws_iam_role" "mgn_replication_server" {
  name               = "AWSApplicationMigrationReplicationServerRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mgn_replication_server" {
  role       = aws_iam_role.mgn_replication_server.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationReplicationServerPolicy"
}

# ==============================================================================
# AWSApplicationMigrationConversionServerRole
#
# Attached to conversion servers that MGN launches to convert source disks
# into EBS volumes during the cutover process.
# ==============================================================================

resource "aws_iam_role" "mgn_conversion_server" {
  name               = "AWSApplicationMigrationConversionServerRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mgn_conversion_server" {
  role       = aws_iam_role.mgn_conversion_server.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationConversionServerPolicy"
}

# ==============================================================================
# AWSApplicationMigrationMGHRole
#
# Allows MGN to report migration progress to AWS Migration Hub (MGH),
# providing a unified view of migration status across services.
# ==============================================================================

resource "aws_iam_role" "mgn_mgh" {
  name               = "AWSApplicationMigrationMGHRole"
  assume_role_policy = data.aws_iam_policy_document.mgn_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mgn_mgh" {
  role       = aws_iam_role.mgn_mgh.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationMGHAccess"
}

# ==============================================================================
# AWSApplicationMigrationLaunchInstanceWithDrsRole
#
# Applied to instances launched by MGN that also integrate with Elastic
# Disaster Recovery (DRS). Combines SSM core access (for Session Manager
# and Patch Manager) with the DRS EC2 instance policy.
# ==============================================================================

resource "aws_iam_role" "mgn_launch_with_drs" {
  name               = "AWSApplicationMigrationLaunchInstanceWithDrsRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Grants SSM agent permissions needed for remote management post-migration.
resource "aws_iam_role_policy_attachment" "mgn_launch_with_drs_ssm" {
  role       = aws_iam_role.mgn_launch_with_drs.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Grants DRS-specific permissions for instances enrolled in both MGN and DRS.
resource "aws_iam_role_policy_attachment" "mgn_launch_with_drs_edr" {
  role       = aws_iam_role.mgn_launch_with_drs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryEc2InstancePolicy"
}

# ==============================================================================
# AWSApplicationMigrationLaunchInstanceWithSsmRole
#
# Applied to instances launched by MGN without DRS integration. SSM core
# access enables Session Manager, Run Command, and patch compliance on
# migrated instances without requiring open SSH ports.
# ==============================================================================

resource "aws_iam_role" "mgn_launch_with_ssm" {
  name               = "AWSApplicationMigrationLaunchInstanceWithSsmRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mgn_launch_with_ssm" {
  role       = aws_iam_role.mgn_launch_with_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ==============================================================================
# AWSApplicationMigrationAgentRole
# - Keep this role if MGN needs to assume it internally
# ==============================================================================

resource "aws_iam_role" "mgn_agent" {
  name               = "AWSApplicationMigrationAgentRole"
  assume_role_policy = data.aws_iam_policy_document.mgn_agent_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mgn_agent" {
  role       = aws_iam_role.mgn_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationAgentPolicy_v2"
}

# ==============================================================================
# MGN Agent Installation User
#
# Dedicated IAM user whose access key is supplied to the source-side agent
# installer. Using a purpose-built user (rather than a role) is required
# because the Azure VM cannot assume an IAM role directly.
# ==============================================================================

resource "aws_iam_user" "mgn_agent" {
  name = "mgn-agent-user"
  path = "/service-users/"
}

resource "aws_iam_user_policy_attachment" "mgn_agent" {
  user       = aws_iam_user.mgn_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AWSApplicationMigrationAgentPolicy"
}

# ==============================================================================
# MGN Agent Access Key
#
# Generated once and stored in Secrets Manager below. Never stored in
# Terraform outputs or state files that may be committed to version control.
# ==============================================================================

resource "aws_iam_access_key" "mgn_agent" {
  user = aws_iam_user.mgn_agent.name
}

# ==============================================================================
# Secrets Manager Secret for MGN Agent Credentials
#
# Centralizes the agent's access key so install.sh can retrieve it via
# `aws secretsmanager get-secret-value` without embedding credentials in
# scripts or environment variables. recovery_window_in_days = 0 allows
# immediate deletion during teardown in test environments.
# ==============================================================================

resource "aws_secretsmanager_secret" "mgn_agent" {
  name                    = "mgn-agent-credentials"
  description             = "AWS credentials for AWS MGN replication agent install"
  recovery_window_in_days = 0

  tags = {
    Name    = "mgn-agent-credentials"
    Service = "mgn"
  }
}

# Stores the access key ID and secret as a JSON object so consumers can
# parse individual fields with `jq` without string manipulation.
resource "aws_secretsmanager_secret_version" "mgn_agent" {
  secret_id = aws_secretsmanager_secret.mgn_agent.id

  secret_string = jsonencode({
    username          = aws_iam_user.mgn_agent.name
    access_key_id     = aws_iam_access_key.mgn_agent.id
    secret_access_key = aws_iam_access_key.mgn_agent.secret
  })
}
