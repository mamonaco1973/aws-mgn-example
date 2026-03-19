output "vpc_id" {
  description = "MGN VPC ID"
  value       = aws_vpc.mgn.id
}

output "staging_subnet_id" {
  description = "MGN staging subnet ID"
  value       = aws_subnet.staging.id
}

output "target_security_group_id" {
  description = "Security group for migrated test instances"
  value       = aws_security_group.mgn_target.id
}

output "next_step" {
  description = "Next step after AWS side is ready"
  value       = "Install the AWS MGN agent on the Azure source VM"
}