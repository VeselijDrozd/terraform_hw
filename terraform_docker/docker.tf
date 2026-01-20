terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  required_version = ">= 1.12.0"
}

provider "docker" {
  host = "ssh://${var.vm_user}@${local.vm_ip}:${var.ssh_port}"
  ssh_opts = [
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-i", var.ssh_privkey_path
  ]
}

 # Берем инфу из другого корня.
data "terraform_remote_state" "vm" {
  backend = "local"
  
  config = {
    path = "../terraform_yc/terraform.tfstate"
  }
}

locals {
  vm_ip = data.terraform_remote_state.vm.outputs.vm_ip
}

resource "random_password" "mysql_root_password" {
  length = 16
}

resource "random_password" "mysql_user_password" {
  length = 12
}

resource "random_password" "mysql_database_name" {
  length      = 8
  special     = false
}

resource "docker_image" "mysql" {
  name         = "mysql:8"
  keep_locally = true
}

resource "docker_container" "mysql" {
  name  = "mysql_server_${random_password.mysql_database_name.result}"
  
  image = docker_image.mysql.image_id
  
  ports {
    ip       = "127.0.0.1"
    external = 3306
    internal = 3306
  }
  
  env = [
    "MYSQL_ROOT_PASSWORD=${random_password.mysql_root_password.result}",
    "MYSQL_DATABASE=${random_password.mysql_database_name.result}",
    "MYSQL_USER=${var.db_user}",
    "MYSQL_PASSWORD=${random_password.mysql_user_password.result}"
  ]
  
  restart = "unless-stopped"

  volumes {
    volume_name    = "mysql_data_${random_password.mysql_database_name.result}"
    container_path = "/var/lib/mysql"
  }
  
  # Зависимости
  depends_on = [
    docker_image.mysql,
    random_password.mysql_root_password,
    random_password.mysql_user_password,
    random_password.mysql_database_name
  ]
}
