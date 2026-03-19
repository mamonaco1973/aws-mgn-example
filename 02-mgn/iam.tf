# ==============================================================================
# IAM data sources
# ==============================================================================

data "aws_caller_identity" "current" {}

# ==============================================================================
# IAM assume-role policies
# ==============================================================================

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

    condition {
      test     = "StringLike"
      variable = "sts:SourceIdentity"
      values   = ["s-*"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# ==============================================================================
# AWSApplicationMigrationReplicationServerRole
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
# ==============================================================================

resource "aws_iam_role" "mgn_launch_with_drs" {
  name               = "AWSApplicationMigrationLaunchInstanceWithDrsRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mgn_launch_with_drs_ssm" {
  role       = aws_iam_role.mgn_launch_with_drs.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "mgn_launch_with_drs_edr" {
  role       = aws_iam_role.mgn_launch_with_drs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticDisasterRecoveryEc2InstancePolicy"
}

# ==============================================================================
# AWSApplicationMigrationLaunchInstanceWithSsmRole
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
# ==============================================================================

resource "aws_iam_role" "mgn_agent" {
  name               = "AWSApplicationMigrationAgentRole"
  assume_role_policy = data.aws_iam_policy_document.mgn_agent_assume_role.json
}

resource "aws_iam_role_policy_attachment" "mgn_agent" {
  role       = aws_iam_role.mgn_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSApplicationMigrationAgentPolicy_v2"
}