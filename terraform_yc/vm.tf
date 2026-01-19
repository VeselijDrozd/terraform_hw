terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 1.12.0"
}
provider "yandex" {
  token = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
}

resource "yandex_vpc_network" "docker_vm_net" {
  name = "docker-vm-network"
}

resource "yandex_vpc_subnet" "docker_vm_subnet" {
  v4_cidr_blocks = ["192.168.10.0/24"]
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.docker_vm_net.id
}

resource "yandex_compute_instance" "docker_host" {
  name        = "docker-host"
  platform_id = "standard-v3"
  zone        = "ru-central1-d"
  
  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8lcd9f54ldmonh1d72" # Ubuntu 22.04
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.docker_vm_subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "${var.vm_user}:${file(var.ssh_pubkey_path)}"
  }

  # Ansible provisioner для установки Docker
  provisioner "remote-exec" {
    inline = [    
      "curl -fsSL https://get.docker.com -o get-docker.sh",
      "sudo sh get-docker.sh",
      "sudo usermod -aG docker ubuntu"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.ssh_privkey_path)
      host        = self.network_interface.0.nat_ip_address
    }
  }
}

output "vm_ip" {
  value = yandex_compute_instance.docker_host.network_interface.0.nat_ip_address
  description = "VM IP address"
}

output "vm_user" {
  value       = var.vm_user
  description = "SSH username for the VM"
}

output "ssh_port" {
  value       = var.ssh_port
  description = "SSH port"
}
