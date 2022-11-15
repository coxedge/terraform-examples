# Provisioning an RKE2 cluster with Terraform on CoxEdge

This example provisions an RKE2 cluster on CoxEdge using Terraform. The cluster consists of 3 nodes, with all nodes acting as both etcd, control plane, and worker nodes.

## Requirements
- [CoxEdge account](https://www.cox.com/business/edge.html)
- [CoxEdge API key](https://api.coxedge.com/)
- [Terraform](https://www.terraform.io/downloads.html) 0.13.x
- [Terraform Provider for CoxEdge](https://github.com/coxedge/terraform-provider-coxedge)

## Setup

### Install the Terraform Provider for CoxEdge

The Terraform Provider for CoxEdge is not yet available in the Terraform Registry. To install the provider, follow the instructions in the [README](https://github.com/coxedge/terraform-provider-coxedge) of the provider's GitHub repository.

```bash
mkdir -p ~/tmp/terraform-provider-coxedge
cd ~/tmp/terraform-provider-coxedge
git clone https://github.com/coxedge/terraform-provider-coxedge.git
cd terraform-provider-coxedge
bash compile-install.sh
```

### Clone this repository

In this section, you will clone this repository to your local machine.

```bash
git clone https://github.com/coxedge/terraform-examples.git
cd terraform-examples/rancher/rke2/3-node-cluster
```

### Setup your environment secrets

We will use environment variables to store the API key and other sensitive information. You can use a different method if you prefer.

```bash
export coxedge_api_key=your-api-key # Example: export coxedge_api_key=1234567890abcdef1234567890abcdef
export coxedge_organization_id=your-organization-id  # Example: export coxedge_organization_id=123456-7890-abcd-ef123456789
export coxedge_environment_name=your-environment-name # Example: export coxedge_environment_name=dev
export rancher_url=your-rancher-url # Example: export coxedge_environment_id=https://rancher.example.com
export rancher_token=your-rancher-token # Example: export coxedge_environment_id=token-1234567890abcdef1234567890abcdef
```

### Initialize Terraform

We need to initialize Terraform. This will download the required providers. Note: We already installed the CoxEdge provider in the previous step.

```bash
terraform init
```

## Provision the cluster

Now that we have the everything setup, we can test our Terraform configuration before provisioning the cluster.

```bash
terraform plan
```

If the plan looks good, we can provision the cluster.

```bash
terraform apply
```

You can monitor the progress of the cluster provisioning in the Rancher UI under Cluster Management > Clusters.

# What does this Terraform script do?

The script starts off by provisioning 3 nodes in the specified environment. The nodes are provisioned with the following configuration:

- 2 vCPUs
- 8 GB RAM
- 32 GB root disk
- 40 GB data disk

In this example, we are creating an RKE2 cluster in Rancher then we are deploying nodes in the CoxEdge then using the cloud-init feature to deploy the Rancher agent. This this point Rancher will take over the provisioning of the cluster.

# Cleanup

When you are done with the cluster, you can destroy it using the following command.

```bash
terraform destroy
```
