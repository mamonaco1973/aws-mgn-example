# ==============================================================================
# Security group for migrated test / cutover instances
# ==============================================================================

resource "aws_security_group" "mgn_target" {
  name        = "${var.name_prefix}-target-sg"
  description = "Security group for MGN-launched test instances"
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
# MGN service initialization
# - Uses AWS CLI because that is the supported automation path
# - Safe first pass for a lab / demo repo
# ==============================================================================

resource "null_resource" "mgn_initialize" {
  count = var.create_mgn_init ? 1 : 0

  triggers = {
    aws_region                        = var.aws_region
    staging_subnet_id                 = aws_subnet.staging.id
    replication_server_instance_type  = var.replication_server_instance_type
    use_private_ip_for_replication    = tostring(var.use_private_ip_for_replication)
    target_security_group_id          = aws_security_group.mgn_target.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      bash scripts/init_mgn.sh \
        "${var.aws_region}" \
        "${aws_subnet.staging.id}" \
        "${var.replication_server_instance_type}" \
        "${var.use_private_ip_for_replication}" \
        "${aws_security_group.mgn_target.id}"
    EOT
  }

  depends_on = [
    aws_subnet.staging,
    aws_security_group.mgn_target
  ]
}