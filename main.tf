terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}

resource "yandex_compute_disk" "boot_disk" {
  name     = "${var.name_prefix}-boot-disk"
  zone     = var.zone
  image_id = var.image_id

  type = var.instance_resources.disk.disk_type
  size = var.instance_resources.disk.disk_size
}

resource "yandex_compute_instance" "this" {
  name                      = "${var.name_prefix}-linux-vm"
  allow_stopping_for_update = true
  platform_id               = var.instance_resources.platform_id
  zone                      = var.zone

  resources {
    cores  = var.instance_resources.cores
    memory = var.instance_resources.memory
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot_disk.id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.private.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}

data "yandex_vpc_network" "default" {
  name = "default"
}

resource "yandex_vpc_subnet" "private" {
  name           = keys(var.subnets)[0]
  zone           = var.zone
  v4_cidr_blocks = var.subnets[keys(var.subnets)[0]]
  network_id     = data.yandex_vpc_network.default.id
}

resource "yandex_mdb_postgresql_cluster" "postgres" {
  name        = "${var.name_prefix}-postgres"
  environment = "PRESTABLE"
  network_id  = data.yandex_vpc_network.default.id

  config {
    version = 14
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 20
    }
  }

  database {
    name  = "${var.name_prefix}-db"
    owner = "my-name"
  }

  user {
    name       = "my-name"
    password   = "Test1234"
    conn_limit = 50
    permission {
      database_name = "${var.name_prefix}-db"
    }
    settings = {
      default_transaction_isolation = "read committed"
      log_min_duration_statement    = 5000
    }
  }

  host {
    zone      = var.zone
    subnet_id = yandex_vpc_subnet.private.id
  }
}

output "internal_ip_address_vm" {
  description = "Internal IP address of VM"
  value       = yandex_compute_instance.this.network_interface.0.ip_address
}

output "external_ip_address_vm" {
  description = "External IP address of VM"
  value       = yandex_compute_instance.this.network_interface.0.nat_ip_address
}

output "postgres_cluster_id" {
  description = "PostgreSQL Cluster ID"
  value       = yandex_mdb_postgresql_cluster.postgres.id
}

output "postgres_cluster_status" {
  description = "PostgreSQL Cluster Status"
  value       = yandex_mdb_postgresql_cluster.postgres.status
}

output "subnet_id" {
  description = "Subnet ID"
  value       = yandex_vpc_subnet.private.id
}

output "vm_cores" {
  description = "VM CPU Cores"
  value       = yandex_compute_instance.this.resources.0.cores
}

output "vm_memory" {
  description = "VM Memory (GB)"
  value       = yandex_compute_instance.this.resources.0.memory
}

