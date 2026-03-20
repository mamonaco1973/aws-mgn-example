# ================================================================================
# Source Instance IAM Role
#
# Attached to the source EC2 instance via an instance profile. Grants:
#   - SSM connectivity (Session Manager, Run Command, patch compliance)
#   - Read access to the mgn-agent-credentials secret in us-east-1 so
#     user-data can retrieve the MGN agent credentials at boot without
#     hardcoding them in the script.
# ================================================================================

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "source_instance" {
  name = "${var.prefix}-source-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM — enables Session Manager access without requiring open SSH port.
resource "aws_iam_role_policy_attachment" "source_ssm" {
  role       = aws_iam_role.source_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Secrets Manager — allows user-data to fetch MGN agent credentials at boot.
# Scoped to the specific secret created in 01-mgn/iam.tf.
resource "aws_iam_role_policy" "source_read_mgn_secret" {
  name = "${var.prefix}-read-mgn-secret"
  role = aws_iam_role.source_instance.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:mgn-agent-credentials*"
    }]
  })
}

# ================================================================================
# Instance Profile
# ================================================================================

resource "aws_iam_instance_profile" "source_instance" {
  name = "${var.prefix}-source-instance-profile"
  role = aws_iam_role.source_instance.name
}
