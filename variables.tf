variable "proxmox_api_url" {
  description = "Proxmox API base URL, e.g. https://pve.local:8006."
  type        = string
}

variable "cluster_name" {
  description = "Talos cluster name."
  type        = string
  default     = "dmz"
}

variable "talos_version" {
  description = "Talos version, e.g. 1.9.5."
  type        = string
}

variable "vlan_id" {
  description = "VLAN tag for all cluster nodes. -1 for untagged."
  type        = number
  default     = -1
}
