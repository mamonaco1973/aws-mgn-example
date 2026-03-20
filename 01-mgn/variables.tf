# ================================================================================
# Variables — 02-mgn
#
# Input variables for the AWS MGN target environment. Defaults target
# us-east-1 with a dedicated /16 VPC to avoid overlap with Azure (10.0/16).
# ================================================================================

# Determines which AWS region receives migrated workloads. Should match
# or be close to the Azure source region to reduce replication latency.
variable "aws_region" {
  description = "AWS region for the MGN target environment"
  type        = string
  default     = "us-east-1"
}

# Prepended to every AWS resource name for easy identification and to
# avoid collisions when multiple MGN environments share an account.
variable "name_prefix" {
  description = "Prefix for all AWS resources"
  type        = string
  default     = "mgn"
}

# VPC CIDR is intentionally non-overlapping with the Azure source network
# (10.0.0.0/16) so future VPN or Direct Connect peering stays conflict-free.
variable "vpc_cidr" {
  description = "CIDR block for the MGN VPC"
  type        = string
  default     = "10.50.0.0/16"
}

# Hosts internet-facing resources (NAT GW, bastion, cutover instances).
variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.50.1.0/24"
}

# MGN replication servers land here during active replication. Keeping them
# in a dedicated subnet makes it easy to apply restrictive NACLs later.
variable "staging_subnet_cidr" {
  description = "CIDR block for the MGN staging subnet"
  type        = string
  default     = "10.50.2.0/24"
}

# t3.small satisfies MGN's minimum requirement for replication servers.
# Upsize to t3.medium or larger for high-throughput replication jobs.
variable "replication_server_instance_type" {
  description = "Instance type for MGN replication servers"
  type        = string
  default     = "t3.medium"
}

# When false, replication traffic flows over the public IP — suitable for
# internet-routed demos. Set true when a VPN or Direct Connect is in place.
variable "use_private_ip_for_replication" {
  description = "Whether to use private IP for replication traffic"
  type        = bool
  default     = false
}

# Controls whether init_mgn.sh runs automatically after apply. Set false
# to skip CLI initialization (e.g., when MGN is already initialized).
variable "create_mgn_init" {
  description = "Run MGN initialization after terraform apply"
  type        = bool
  default     = true
}
