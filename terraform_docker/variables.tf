variable "vm_user" {
 type    = string
 default = "ubuntu"
}

variable "ssh_pubkey_path" {
  type      = string
  sensitive = true
}

variable "ssh_privkey_path" {
  type      = string
  sensitive = true
}

variable "ssh_port" {
  type = number
}

variable "db_user" {
  type = string
}

variable "yc_token" {
  type      = string
  sensitive = true
}

variable "yc_cloud_id" {
  type      = string
  sensitive = true
}

variable "yc_folder_id" {
  type      = string
  sensitive = true
}
