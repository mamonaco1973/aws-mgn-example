# ================================================================================
# Outputs — 02-mgn
#
# Surfaces the key resource IDs needed when configuring the MGN agent on
# the Azure source VM and when running post-migration validation.
# ================================================================================

# Passed to the MGN agent configuration to scope replication to this VPC.
output "vpc_id" {
  description = "MGN VPC ID"
  value       = aws_vpc.mgn.id
}

# Referenced in the replication template so MGN places replication servers
# in the dedicated staging subnet rather than the public subnet.
output "staging_subnet_id" {
  description = "MGN staging subnet ID"
  value       = aws_subnet.staging.id
}

# Applied to test and cutover instances launched by MGN to allow SSH and
# HTTP access for post-migration smoke tests.
output "target_security_group_id" {
  description = "Security group for migrated test instances"
  value       = aws_security_group.mgn_target.id
}

output "public_subnet_id" {
  description = "Public subnet ID for test and cutover instances"
  value       = aws_subnet.public.id
}

# Reminds the operator of the manual step required after Terraform apply
# completes — the AWS MGN agent must be installed on the Azure source VM.
output "next_step" {
  description = "Next step after AWS side is ready"
  value       = "Install the AWS MGN agent on the Azure source VM"
}
