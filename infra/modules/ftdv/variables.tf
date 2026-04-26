variable "resource_group_name" {
  description = "Resource group for FTDv."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "mgmt_subnet_id" {
  description = "Subnet ID for FTDv Nic0 (management, private only)."
  type        = string
}

variable "diagnostic_subnet_id" {
  description = "Subnet ID for FTDv Nic1 (diagnostic)."
  type        = string
}

variable "outside_subnet_id" {
  description = "Subnet ID for FTDv Nic2 (outside, public-facing)."
  type        = string
}

variable "inside_subnet_id" {
  description = "Subnet ID for FTDv Nic3 (inside)."
  type        = string
}

variable "admin_password" {
  description = "FTDv admin password used in Day-0 JSON."
  type        = string
  sensitive   = true
}

variable "reg_key" {
  description = "cdFMC registration key from SCC."
  type        = string
  sensitive   = true
}

variable "nat_id" {
  description = "cdFMC NAT ID from SCC."
  type        = string
  sensitive   = true
}

variable "image_plan" {
  description = "Cisco FTDv marketplace plan."
  type        = string
}

variable "image_version" {
  description = "FTDv image version."
  type        = string
}

variable "vm_size" {
  description = "Azure VM size. FTD 10.x requires Dsv3 or Fsv2 family. Default sized for FTDv5 (4 vCPU / 8 GB Cisco-recommended); D4s_v3 also covers FTDv10 and FTDv20. For FTDv30 step up to D8s_v3; for FTDv50 step up to D16s_v3."
  type        = string
  default     = "Standard_D4s_v3"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}
