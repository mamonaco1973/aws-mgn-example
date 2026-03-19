# ================================================================================
# Variables — 01-azure
#
# Input variables for the Azure source environment. Defaults are sized for
# a lightweight demo deployment (cheapest B-series VM, Central US).
# ================================================================================

# Prepended to every Azure resource name to keep deployments identifiable
# and avoid collisions when multiple environments share a subscription.
variable "prefix" {
  description = "Resource naming prefix"
  type        = string
  default     = "mgn"
}

# Region selection — Central US is used as a neutral default. Change to
# whichever region is closest to the AWS target region for lower latency
# during replication.
variable "location" {
  description = "Azure region"
  type        = string
  default     = "Central US"
}

# Standard_B1s is the smallest general-purpose size and sufficient for the
# demo workload (Apache serving a static page). Upsize for real migrations.
variable "vm_size" {
  description = "VM size"
  type        = string
  default     = "Standard_B1s"
}

# Used for both the OS-level account and the SSH public-key association.
# Must match the username embedded in the cloud-init script if changed.
variable "admin_username" {
  description = "Admin username"
  type        = string
  default     = "ubuntu"
}
