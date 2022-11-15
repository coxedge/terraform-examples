terraform {
  required_providers {
    coxedge = {
      version = "0.1.1"
      source = "coxedge.com/cox/coxedge"
    }    
    random = {
      source = "hashicorp/random"
      version = "3.4.3"
    }
    tls = {
      source  = "hashicorp/tls"
    }
    ssh = {
      source = "loafoe/ssh"
      version = "2.3.0"
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

# Firewall Rules for rke2 management/worker nodes
resource "coxedge_network_policy_rule" "rke2-nodes" {
  organization_id  = var.coxedge_organization_id
  environment_name = var.coxedge_environment_name
  network_policy {
    workload_id = coxedge_workload.rke2-nodes.id
    description = "Allow http from the internet"
    protocol    = "TCP"
    type        = "INBOUND"
    action      = "ALLOW"
    source      = "0.0.0.0/0"
    port_range  = "22"
  }
  network_policy {
    workload_id = coxedge_workload.rke2-nodes.id
    description = "Allow kubeapi from Internet"
    protocol    = "TCP"
    type        = "INBOUND"
    action      = "ALLOW"
    source      = "0.0.0.0/0"
    port_range  = "6443"
  }
  network_policy {
    workload_id = coxedge_workload.rke2-nodes.id
    description = "Allow http from the internet"
    protocol    = "TCP"
    type        = "INBOUND"
    action      = "ALLOW"
    source      = "0.0.0.0/0"
    port_range  = "80"
  }
  network_policy {
    workload_id = coxedge_workload.rke2-nodes.id
    description = "Allow https from the internet"
    protocol    = "TCP"
    type        = "INBOUND"
    action      = "ALLOW"
    source      = "0.0.0.0/0"
    port_range  = "443"
  }
}

# rke2 management/worker nodes
resource "coxedge_workload" "rke2-nodes" {
  name             = "rke2-edge-nodes"
  organization_id  = var.coxedge_organization_id
  environment_name = var.coxedge_environment_name
  type             = "VM"
  image            = "stackpath-edge/ubuntu-2004-focal:v202102241556"
  add_anycast_ip_address = true
  first_boot_ssh_key = tls_private_key.ssh.public_key_openssh
  specs            = "SP-3"
  persistent_storages {
    path = "/var/lib/rancher"
    size = 40
  }

  deployment {
    name               = "cox"
    enable_autoscaling = false
    pops               = [var.pop]
    instances_per_pop  = 3
  }
}

# Creating a random token for the cluster
resource "random_password" "token" {
  length           = 64
  special          = false
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

resource "null_resource" "bootstrap_cluster" {
  depends_on = [
    coxedge_workload.rke2-nodes
  ]

  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "bash bootstrap-cluster.sh > bootstrap-cluster.log"

    environment = {
      coxEdgeApiKey = var.coxedge_api_key
      coxEdgeOrganizationId = var.coxedge_organization_id
      coxEdgeEnvironmentName = var.coxedge_environment_name
      coxEdgeNodeWorkloadName = coxedge_workload.rke2-nodes.name
      coxEdgeNodeWorkloadCount = coxedge_workload.rke2-nodes.deployment[0].instances_per_pop
      clusterToken = random_password.token.result
      sshUser = "ubuntu"
      debug = "true"
     }
  }
}