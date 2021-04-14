# Basic Azure VM TF config intended for RocketChat install

## Setup

Follow the relevant[Terraform tutorial](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/azure-get-started) to install Terraform and the Azure CLI, and authenticate with Azure.

## Deployment

Deployment should be straightforward with Terraform. Check out `main.tf` for relevant vars which can be modified (e.g. `prefix` for the installation prefix, `location` for Azure datacenter). You must provide a `ssh_public_key_file` to install for authenticating to the VM after deployment.

To see what changes will be applied, run `terraform plan` - e.g.:

    terraform plan -var="ssh_public_key_file=~/.ssh/id_rsa"

To apply the changes, run `terraform apply` with the same arguments.

At this point, you should have a set of resources created in Azure, including a parent Resource Group, VM, and associated items related to networking and storage.
