terraform {
  required_providers {
    coxedge = {
      version = "0.1.1"
      source = "coxedge.com/cox/coxedge"
    }    
    rancher2 = {
      source = "rancher/rancher2"
    }
  }
}

variable "coxedge_api_key" {
  description = "value of coxedge_api_key"
  type = string
  default = "Replace with your API key"
}

variable "coxedge_organization_id" {
  description = "value of coxedge_organization_id"
  type = string
  default = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
}

variable "coxedge_environment_name" {
  description = "value of coxedge_environment_name"
  type = string
  default = "Replace with your environment name"
}

variable "pop" {
  description = "value of pop"
  type = string
  default = "PVD"
}

provider "coxedge" {
  key = var.coxedge_api_key
}

variable "rancher_url" {
  description = "value of rancher_url"
  type = string
  default = "https://rancher.example.com"
}

variable "rancher_token" {
  description = "value of rancher_token"
  type = string
  default = "Replace with your Rancher token"
}

provider "rancher2" {
  api_url = var.rancher_url
  token_key = var.rancher_token
  insecure = true
}

resource "rancher2_cluster_v2" "rke2-cluster" {
  name = "rke2-coxedge-cluster"
  kubernetes_version = "v1.24.4+rke21"
  fleet_namespace = "fleet-default"
}

resource "coxedge_network_policy_rule" "rke2-node-nodes" {
  organization_id  = var.coxedge_organization_id
  environment_name = var.coxedge_environment_name
  network_policy {
    workload_id = coxedge_workload.rke2-node-nodes.id
    description = "Allow SSH from Jump"
    protocol    = "TCP"
    type        = "INBOUND"
    action      = "ALLOW"
    source      = "98.190.75.2/32"
    port_range  = "22"
  }
  network_policy {
    workload_id = coxedge_workload.rke2-node-nodes.id
    description = "Allow SSH from Internet"
    protocol    = "TCP"
    type        = "INBOUND"
    action      = "ALLOW"
    source      = "0.0.0.0/0"
    port_range  = "22"
  }
  network_policy {
    workload_id = coxedge_workload.rke2-node-nodes.id
    description = "Allow HTTP from Internet"
    protocol    = "TCP"
    type        = "INBOUND"
    action      = "ALLOW"
    source      = "0.0.0.0/0"
    port_range  = "80"
  }
  network_policy {
    workload_id = coxedge_workload.rke2-node-nodes.id
    description = "Allow HTTPS from Internet"
    protocol    = "TCP"
    type        = "INBOUND"
    action      = "ALLOW"
    source      = "0.0.0.0/0"
    port_range  = "443"
  }
  network_policy {
    workload_id = coxedge_workload.rke2-node-nodes.id
    description = "Allow kubectl from Jump"
    protocol    = "TCP"
    type        = "INBOUND"
    action      = "ALLOW"
    source      = "98.190.75.2/32"
    port_range  = "6443"
  }
  network_policy {
    workload_id = coxedge_workload.rke2-node-nodes.id
    description = "Allow http to Internet"
    protocol    = "TCP"
    type        = "OUTBOUND"
    action      = "ALLOW"
    source      = "0.0.0.0/0"
    port_range  = "80"
  }
  network_policy {
    workload_id = coxedge_workload.rke2-node-nodes.id
    description = "Allow https to Internet"
    protocol    = "TCP"
    type        = "OUTBOUND"
    action      = "ALLOW"
    source      = "0.0.0.0/0"
    port_range  = "443"
  }
}

# Master/Worker Nodes
resource "coxedge_workload" "rke2-node-nodes" {
  name             = "rke2-ran-node"
  organization_id  = var.coxedge_organization_id
  environment_name = var.coxedge_environment_name
  type             = "VM"
  image            = "stackpath-edge/ubuntu-2004-focal:v202102241556"
  add_anycast_ip_address = true
  first_boot_ssh_key = tls_private_key.ssh.public_key_openssh
  specs            = "SP-2"
  persistent_storages {
    path = "/var/lib/rancher"
    size = 40
  }

  user_data = templatefile("cloud-init.tpl", {
    cluster_token = rancher2_cluster_v2.rke2-cluster.cluster_registration_token.0.token
    coxedge_organization_id  = var.coxedge_organization_id
    coxedge_environment_name = var.coxedge_environment_name
    rancher_url = var.rancher_url
    ssh_public_key = tls_private_key.ssh.public_key_openssh
  })

  deployment {
    name               = "cox"
    enable_autoscaling = false
    pops               = [var.pop]
    instances_per_pop  = 3
  }
}

# Creating ssh key pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_pem" { 
  filename = "private.pem"
  content = tls_private_key.ssh.private_key_pem
}
