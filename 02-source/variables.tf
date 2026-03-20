variable "prefix" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "mgn"
}

variable "aws_region" {
  description = "AWS region for the source EC2 instance"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the source VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the source subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the source VM"
  type        = string
  default     = "t3.medium"
}

variable "admin_username" {
  description = "SSH username (Amazon Linux 2 default)"
  type        = string
  default     = "ec2-user"
}
