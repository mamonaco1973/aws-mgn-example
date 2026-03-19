# ================================================================================
# Amazon Linux 2 AMI — us-east-2
#
# Resolved dynamically from the Amazon account (137112412989). Amazon Linux 2
# uses a kernel maintained and tested by AWS alongside the MGN agent — no
# kernel compilation issues or version ceiling problems.
# ================================================================================

data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["137112412989"] # Amazon

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ================================================================================
# Source EC2 Instance — us-east-2
#
# Amazon Linux 2. User-data installs Apache (httpd) so the workload can be
# verified before and after migration.
# ================================================================================

resource "aws_instance" "main" {
  ami                    = data.aws_ami.amzn2.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.vm_key.key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.main.id]

  user_data = file("scripts/user_data.sh")

  tags = {
    Name = "${var.prefix}-source-vm"
  }
}

# ================================================================================
# Outputs
# ================================================================================

output "vm_public_dns" {
  value       = aws_instance.main.public_dns
  description = "Public DNS name of the source EC2 instance"
}

output "vm_public_ip" {
  value       = aws_instance.main.public_ip
  description = "Public IP address of the source EC2 instance"
}
