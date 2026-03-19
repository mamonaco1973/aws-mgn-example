# ==============================================================================
# Security Group — MGN Replication Servers and Launched Instances
#
# This SG is used for two purposes:
#   1. Replication servers (passed via --replication-servers-security-groups-ids)
#      TCP 1500 inbound is required for the source agent to stream disk data.
#   2. Test launch and cutover instances — SSH (22) and HTTP (80) for validation.
#
# Open CIDRs are acceptable for a short-lived demo environment.
# ==============================================================================

resource "aws_security_group" "mgn_target" {
  name        = "${var.name_prefix}-target-sg"
  description = "Security group for MGN-launched test and cutover instances"
  vpc_id      = aws_vpc.mgn.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MGN replication data plane — source agent connects to replication servers
  # on TCP 1500 to stream disk data. Required when dataPlaneRouting=PUBLIC_IP.
  ingress {
    description = "MGN replication"
    from_port   = 1500
    to_port     = 1500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-target-sg"
  }
}

# ==============================================================================
# Initialize AWS MGN and create the required account-level templates
#
# Notes
# - For API / CLI initialization, AWS requires:
#   1) IAM roles
#   2) replication template
#   3) launch template
# - We create the IAM roles in iam.tf
# - We then run the AWS CLI from local-exec to finish initialization
# ==============================================================================

resource "null_resource" "mgn_initialize" {
  # Trigger re-initialization whenever network or instance-type config changes,
  # ensuring the replication template stays in sync with Terraform state.
  triggers = {
    aws_region                       = var.aws_region
    staging_subnet_id                = aws_subnet.staging.id
    target_security_group_id         = aws_security_group.mgn_target.id
    replication_server_instance_type = var.replication_server_instance_type
    use_private_ip_for_replication   = tostring(var.use_private_ip_for_replication)
  }

  # Calls init_mgn.sh which runs `aws mgn initialize-service`,
  # creates the replication configuration template, and creates the
  # launch configuration template via the AWS CLI.
  provisioner "local-exec" {
    command = <<-EOT
      bash scripts/init_mgn.sh \
        "${var.aws_region}" \
        "${aws_subnet.staging.id}" \
        "${aws_security_group.mgn_target.id}" \
        "${var.replication_server_instance_type}" \
        "${var.use_private_ip_for_replication}"
    EOT
  }

  # All IAM roles must exist before MGN initialization; the CLI calls fail
  # with AccessDenied if the service-linked roles are not yet propagated.
  depends_on = [
    aws_subnet.staging,
    aws_security_group.mgn_target,
    aws_iam_role.mgn_replication_server,
    aws_iam_role_policy_attachment.mgn_replication_server,
    aws_iam_role.mgn_conversion_server,
    aws_iam_role_policy_attachment.mgn_conversion_server,
    aws_iam_role.mgn_mgh,
    aws_iam_role_policy_attachment.mgn_mgh,
    aws_iam_role.mgn_launch_with_drs,
    aws_iam_role_policy_attachment.mgn_launch_with_drs_ssm,
    aws_iam_role_policy_attachment.mgn_launch_with_drs_edr,
    aws_iam_role.mgn_launch_with_ssm,
    aws_iam_role_policy_attachment.mgn_launch_with_ssm,
    aws_iam_role.mgn_agent,
    aws_iam_role_policy_attachment.mgn_agent
  ]
}
