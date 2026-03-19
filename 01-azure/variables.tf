variable "prefix" {
  description = "Resource naming prefix"
  type        = string
  default     = "mgn"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "Central US"
}

variable "vm_size" {
  description = "VM size"
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Admin username"
  type        = string
  default     = "ubuntu"
}