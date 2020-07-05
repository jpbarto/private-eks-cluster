# Infrastructure as Code for Amazon EKS with a Secondary CIDR Range

## Overview

The following is an example of how to deploy an EKS cluster into an AWS VPC with a secondary CIDR range.  The following code enables the public endpoint of the EKS cluster for convenience.  

## Pre-requisites

The following must be installed onto the system executing the code in this repository:
  * Terraform >v0.12
  * wget
  * AWS CLI v2
  * kubectl

## Getting Started

To deploy an EKS cluster into a VPC using this code please ensure that you specify the target region in `terraform.tfvars`.  Please note that this code creates a VPC for use by the EKS cluster (network is defined in `network.tf`).  If you wish to use a pre-existing VPC please modify `cluster.tf` and `outputs.tf` appropriately.

To launch the code following the typical Terraform workflow:
```bash
terraform init
terraform plan
terraform apply
```

When this has completed (please note the EKS cluster will take approximately 10 min to create) you are left with a `post_apply.sh` shell script.  This has the responsibility of performing final configuration of the K8s cluster and upscaling your worker node count.  Execute this script, without arguments, after applying the Terraform template.

Once completed you should have a functioning K8s cluster in AWS which deploys containers to a secondary CIDR range.

```bash
kubectl get nodes
kubectl run alpine-shell --rm -i --tty --image alpine -- sh
```
