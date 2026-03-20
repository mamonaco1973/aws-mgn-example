# ================================================================================
# Windows Server 2019 AMI — us-east-2
#
# Resolved dynamically from the Amazon account (801119661308). 2019 is the
# more realistic migration source — represents the generation of Windows
# servers organisations are actively looking to move off.
# ================================================================================

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["801119661308"] # Amazon

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ================================================================================
# Security Group — Windows Source VM
#
# RDP (3389) for admin access and HTTP (80) for IIS workload validation.
# MGN replication traffic initiates outbound from the agent — no inbound
# rule required for replication.
# ================================================================================

resource "aws_security_group" "windows" {
  name        = "${var.prefix}-source-windows-sg"
  description = "RDP and HTTP access for Windows source VM"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}-source-windows-sg"
  }
}

# ================================================================================
# Windows Source EC2 Instance — us-east-2
#
# Windows Server 2019. User-data installs IIS so the workload can be verified
# before and after migration. t3.medium — Windows requires more memory than
# the t3.micro used for the Linux instance.
# ================================================================================

resource "aws_instance" "windows" {
  ami                  = data.aws_ami.windows.id
  instance_type        = "t3.medium"
  key_name             = aws_key_pair.vm_key.key_name
  subnet_id            = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.windows.id]
  iam_instance_profile = aws_iam_instance_profile.source_instance.name

  user_data = file("scripts/user_data.ps1")

  tags = {
    Name = "${var.prefix}-source-windows-vm"
  }
}

# ================================================================================
# Outputs
# ================================================================================

output "windows_public_dns" {
  value       = aws_instance.windows.public_dns
  description = "Public DNS name of the Windows source EC2 instance"
}

output "windows_public_ip" {
  value       = aws_instance.windows.public_ip
  description = "Public IP address of the Windows source EC2 instance"
}
