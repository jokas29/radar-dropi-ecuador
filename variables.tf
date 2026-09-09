variable "tenancy_ocid" {
  type        = string
  description = "OCI tenancy OCID (auto-filled by Resource Manager)."
}

variable "region" {
  type        = string
  description = "OCI region (auto-filled by Resource Manager)."
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment where Radar Commerce resources will be created."
}

variable "availability_domain_name" {
  type        = string
  description = "Availability Domain for the Always Free A1 instance."
}

variable "ssh_public_key" {
  type        = string
  description = "Optional SSH public key for emergency administration."
  default     = ""
}

variable "instance_name" {
  type        = string
  description = "Compute instance name."
  default     = "radar-commerce"
}
