# ================================================================================
# Ubuntu 22.04 LTS AMI — us-east-2
#
# Resolved dynamically from the Canonical account (099720109477). 22.04 (Jammy)
# ships with kernel 5.15 which is within MGN's supported range (3.x – 6.8).
# 24.04 AMIs now ship with kernels above 6.8 and will fail agent installation.
# Note: 22.04 AMIs use the hvm-ssd prefix; hvm-ssd-gp3 was introduced with 24.04.
# ================================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ================================================================================
# Source EC2 Instance — us-east-2
#
# Ubuntu 22.04 LTS. User-data installs Apache so the workload can be verified
# before and after migration. 22.04 ships with kernel 5.15 which is within
# MGN's supported ceiling of 6.8.
# ================================================================================

resource "aws_instance" "main" {
  ami                    = data.aws_ami.ubuntu.id
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
