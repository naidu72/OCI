variable "project" {
  description = "Name prefix for all resources."
  type        = string
  default     = "sample-app"
}

variable "ssh_public_key_path" {
  description = "Public key installed on the VMs for the ubuntu user."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH to the VMs. Set this to your own IP (x.x.x.x/32)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "availability_domain_index" {
  description = "Always Free A1 capacity only exists in your home region; pick the AD that has capacity (0-based)."
  type        = number
  default     = 0
}

# Always Free Ampere A1 allowance: 4 OCPU + 24 GB RAM in total, split here across 2 VMs.
variable "vm_ocpus" {
  description = "OCPUs per VM. Keep vm_count * vm_ocpus <= 4 to stay free."
  type        = number
  default     = 2
}

variable "vm_memory_gbs" {
  description = "Memory per VM. Keep vm_count * vm_memory_gbs <= 24 to stay free."
  type        = number
  default     = 12
}

# Always Free block storage: 200 GB in total (boot volumes count toward it, min 47 GB each).
variable "boot_volume_gbs" {
  description = "Boot volume size per VM."
  type        = number
  default     = 50
}

variable "failover_after_seconds" {
  description = "How long the primary database must be unreachable before the standby promotes itself."
  type        = number
  default     = 60
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}
