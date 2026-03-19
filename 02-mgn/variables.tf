variable "aws_region" {
  description = "AWS region for the MGN target environment"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for all AWS resources"
  type        = string
  default     = "mgn"
}

variable "vpc_cidr" {
  description = "CIDR block for the MGN VPC"
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.50.1.0/24"
}

variable "staging_subnet_cidr" {
  description = "CIDR block for the MGN staging subnet"
  type        = string
  default     = "10.50.2.0/24"
}

variable "replication_server_instance_type" {
  description = "Instance type for MGN replication servers"
  type        = string
  default     = "t3.small"
}

variable "use_private_ip_for_replication" {
  description = "Whether to use private IP for replication traffic"
  type        = bool
  default     = false
}

variable "create_mgn_init" {
  description = "Run MGN initialization after terraform apply"
  type        = bool
  default     = true
}