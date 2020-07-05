# private-eks-cluster

This repository is a collection of CloudFormation templates and shell scripts to create an Amazon EKS Kubernetes cluster in an AWS Virtual Private Cloud (VPC) without any Internet connectivity.

## Overview

This collection of CloudFormation templates and Bash shell scripts will deploy an EKS cluster into a VPC with no Internet Gateway (IGW) or NAT Gateway attached.

To do this it will create:
- VPC
- VPC endpoints - for EC2, ECR, STS, AutoScaling, SSM
- VPC endpoint for Proxy (optional) - to an existing web proxy that you have already setup (not required by EKS but assumed you want to pull containers from DockerHub, GCR.io etc)
- IAM Permissions
- EKS Cluster - logging enabled, encrypted secrets, no public endpoint
- OIDC IDP - To allow pods to assume AWS roles
- Auto-scaling Group for Node group (optional) - including optional bootstrap configuration for the proxy
- Fargate Profile (optional) - for running containers on Fargate

Once completed you can (from within the VPC) communicate with your EKS cluster and see a list of running worker nodes.

## Justification

To create an EKS cluster that is fully private and running within a VPC with no internet connection can be a challenge.  A couple of challenges prevent this from happening easily.

First the EKS Cluster resource in CloudFormation does not allow you to specify that you want a private-only endpoint.  [Terraform](https://www.terraform.io/docs/providers/aws/r/eks_cluster.html) currently supports this configuration.

Second, the EKS worker nodes, when they start need to communicate with the EKS master nodes and to do that they require details such as the CA certificate for the EKS master nodes.  Normally, at bootstrap, the EC2 instance can query the EKS control plane and retrieve these details however the EKS service currently does not have support for [VPC endpoints for the EKS control plane](https://github.com/aws/containers-roadmap/issues/298).  Managed node groups can be an offset for this but you may want to customize the underlying host or use a custom AMI.

Third, once launched the instance role of the EC2 worker nodes must be registered with the EKS master node to allow the nodes to communicate with the cluster.

To solve these issues this project takes advantage of all of the flexibility the EKS service makes available to script the creation of a completely private EKS cluster.

> Note that this repository is here for illustration and demonstration purposes only.  The hope is that this repository aids in helping your understanding of how EKS works to manage Kubernetes clusters on your behalf.  It is not intended as production code and should not be adopted as such.

## Quickstart

1. Clone this repository to a machine that has CLI access to your AWS account.
1. Edit the values in `variables.sh`

    1. Set `CLUSTER_NAME` to be a name you choose
    1. Set `REGION` to be an AWS region you prefer, such as us-east-2, eu-west-2, or eu-central-1
    1. Edit `AMI_ID` to be correct for your region

1. Execute `launch_all.sh`

## Getting started

Edit the variable definitions found in `variables.sh`.

These variables are:
 - CLUSTER_NAME - your desired EKS cluster name
 - REGION - the AWS region in which you want the resources created
 - HTTP_PROXY_ENDPOINT_SERVICE_NAME - this is the name of a VPC endpoint service you must have previously created which represents an HTTP proxy (e.g. Squid)
 - KEY_PAIR - the name of an existing EC2 key pair to be used as an SSH key on the worker nodes
 - VERSION - the EKS version you wish to create ('1.16', '1.15', '1.14' etc)
 - AMI_ID - the region-specific AWS EKS worker AMI to use. (See here for the list of managed AMIs)[https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html]
 - INSTANCE_TYPE - the instance type to be used for the worker nodes
 - S3_STAGING_LOCATION - an existing S3 bucket name and optional prefix to which CloudFormation templates and a kubectl binary will be uploaded
 - ENABLE_FARGATE - set to 'true' to enable fargate support, disabled by default as this requires the proxy to be a transparent proxy 
 - FARGATE_PROFILE_NAME - the name for the Fargate profile for running EKS pods on Fargate
 - FARGATE_NAMESPACE - the namespace to match pods to for running EKS pods on Fargate. You must also create this inside the cluster with 'kubectl create namespace fargate' and then launch the pod into that namespace for Fargate to be the target

If you do not have a proxy already configured you can use the cloudformation/proxy.yaml template provided which is a modified version of the template from this guide:
https://aws.amazon.com/blogs/security/how-to-add-dns-filtering-to-your-nat-instance-with-squid/
This will setup a squid proxy in it's own VPC that you can use, along with a VPC endpoint service and test instance. The template can take a parameter: "whitelistedDomains" - a list of whitelisted domains separated by a comma for the proxy whitelist. This is refreshed on a regular basis, so modifying directly on the EC2 instance is not advised.
```
aws cloudformation create-stack --stack-name filtering-proxy --template-body file://cloudformation/proxy.yaml --capabilities CAPABILITY_IAM
export ACCOUNT_ID=$(aws sts get-caller-identity --output json | jq -r '.Account')
export HTTP_PROXY_ENDPOINT_SERVICE_NAME=$(aws ec2 describe-vpc-endpoint-services --output json | jq -r '.ServiceDetails[] | select(.Owner==env.ACCOUNT_ID) | .ServiceName')
echo $HTTP_PROXY_ENDPOINT_SERVICE_NAME
```
After, enter the output of the proxy endpoint service name into the `variables.sh` file.

 Once these values are set you can execute `launch_all.sh` and get a coffee. This will take approximately 10 - 15 min to create the vpc, endpoints, cluster, and worker nodes.

 After this is completed you will have an EKS cluster that you can review using the AWS console or CLI. You can also remotely access your VPC using an Amazon WorkSpaces, VPN, or similar means. Using the `kubectl` client you should then see something similar to:

 ```bash
 [ec2-user@ip-10-10-40-207 ~]$ kubectl get nodes
NAME                                          STATUS   ROLES    AGE   VERSION
ip-10-0-2-186.eu-central-1.compute.internal   Ready    <none>   45m   v1.13.8-eks-cd3eb0
ip-10-0-4-219.eu-central-1.compute.internal   Ready    <none>   45m   v1.13.8-eks-cd3eb0
ip-10-0-8-46.eu-central-1.compute.internal    Ready    <none>   45m   v1.13.8-eks-cd3eb0
[ec2-user@ip-10-10-40-207 ~]$ kubectl get ds -n kube-system
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
aws-node     3         3         3       3            3           <none>          52m
kube-proxy   3         3         3       3            3           <none>          52m
```

There you go - you now have an EKS cluster in a private VPC!

## Code Explained

`variables.sh` defines key user configurable values that control how the scripts exxecute to create an EKS cluster.  These values control whether Fargate is used to host worker nodes, whether a proxy server is configured on the worker nodes, and whether you would like the EKS master node to be accessible from outside of the VPC.  

`launch_all.sh` sources the values from `variables.sh` and then begins by creating an S3 bucket (if it does not already exist) to host the CloudFormation templates and kubectl binary.  With an S3 bucket in place the script then moves on to deploying the CloudFormation stack defined by `environment.yaml`.  This stack deploys 2 nested stacks, `permissions.yaml` and `network.yaml`.  

`permissions.yaml` creates an IAM role for the EKS cluster, a KMS key to encrypt K8s secrets held on the EKS master node, and an IAM role for the EC2 worker nodes to be created later.

`network.yaml` creates a VPC with no IGW and 3 subnets.  It also creates VPC endpoints for Amazon S3, Amazon ECR, Amazon EC2, EC2 AutoScaling, CloudWatch Logs, STS, and SSM.  If an VPC endpoint service is specified for a proxy server an VPC Endpoint will also be created to point at the proxy server.  

With permissions and a network in place the `launch_all.sh` script next launches an EKS cluster using the AWS CLI.  This cluster will be configured to operate privately, with full logging to CloudWatch logs, Kubernetes secrets encrypted using a KMS key, and with the role created in the `permissions.yaml` CloudFormation template.  The script will then pause while it waits for the cluster to finish creating.

Next the script will configured an OpenID Connect Provider which will be used to allow Kubernetes pods to authenticate against AWS IAM and obtain temporary credentials.  This works in a manner similar to EC2 instance profiles where containers in the pod can then reference AWS credentials as secrets using standard K8s parlance.

After the EKS cluster has been created an the OIDC provider configured the script will then configure your local `kubectl` tool to communicate with the EKS cluster.  Please note this will only work if you have a network path to your EKS master node.  To have this network path you will need to be connected to your VPC over Direct Connect or VPN, or you will have to enable communication with your EKS master node from outside of the VPC.

Next the script will hand control over to `launch_workers.sh` which will again read values from `variables.sh` before proceeding.

`launch_workers.sh` will read values from the previous CloudFormation stack to know what VPC subnets and security groups to use.  The script will retreive the HTTPS endpoint for the EKS master node, and the CA certificate to be used during communication with the master.  It will also request a token for communicating with the EKS master node created by `launch_all.sh`.  

With these values in hand the script will then launch worker nodes to run your K8s pods.  Depending on your configuration of `variables.sh` the script will either apply the `fargate.yaml` CloudFormation template and create a Fargate Profile with EKS, allowing you to run a fully serverless K8s cluster.  Or it will create an EC2 autoscaling group to create EC2 instances in your VPC that will connect with the EKS master node.

To create the EC2 instances the script will first download the `kubectl` binary and store it in S3 for later retreival by the worker nodes.  It will then apply the `eks-workers.yaml` CloudFormation template.  The template will create a launch configuration and autoscaling group that will create EC2 instances to host your pods.

When they first launch the EC2 worker nodes will use the CA certificate and EKS token provided to them to configure themselves and communicate with the EKS master node.  The worker nodes, using Cloud-Init user data, will apply an auth config map to the EKS master node, giving the worker nodes permission to register as worker nodes with the EKS master.  If a proxy has been configured the EC2 instance will configure Docker and Kubelet to use your HTTP proxy.  The EC2 instance will also execute the EKS bootstrap.sh script which is provided by the EKS service AMI to configure the EKS components on the system.  Lastly the EC2 instance will insert an IPTables rule that disallows pods to query the EC2 metadata service.

When the CloudFormation template has been applied and the user data has executed on the EC2 worker nodes the shell script will return and you should now have a fully formed EKS cluster running privately in a VPC.

## EKS Under the covers

Amazon EKS is managed upstream K8s. So all the requirements and capabilities of Kubernetes apply. This is to say that when you create an EKS cluster you are given either a private or public (or both) K8s master mode, managed for you as a service. When you create EC2 instances, hopefully as part of an auto scaling group, those nodes will need to be able to authenticate into the K8s master node and be managed by the master. The node runs the standard Kubelet and Docker daemon and will need the master's name and CA certificate. To do this the Kubelet will query the EKS service or you can provide these as arguments to the bootstrap.sh. After connecting to the master it will receive instruction to launch daemon sets. To do this Kubelet and Docker will need to authenticate themselves into ECR where the DS images are probably kept. Please note that the 1.13 version of Kubelet is compatible with VPC endpoints for ECR but 1.11 and 1.12 will require a proxy server to reach ecr.REGION.amazonaws.com. After pulling down the daemon sets your cluster should be stable and ready for use. For details about configuring proxy servers for Kubelet etc please check out the source code.

## Development notes
---
### configure proxy for docker daemon
https://stackoverflow.com/questions/23111631/cannot-download-docker-images-behind-a-proxy

### authenticate with ECR
https://docs.aws.amazon.com/AmazonECR/latest/userguide/Registries.html#registry_auth

```bash
aws ecr get-login --region eu-west-1 --no-include-email
```

### containers key to worker node operation
602401143452.dkr.ecr.eu-west-1.amazonaws.com/amazon-k8s-cni:v1.5.0
602401143452.dkr.ecr.eu-west-1.amazonaws.com/eks/kube-proxy:v1.11.5
602401143452.dkr.ecr.eu-west-1.amazonaws.com/eks/coredns:v1.1.3
602401143452.dkr.ecr.eu-west-1.amazonaws.com/eks/pause-amd64:3.1

### Docker unable to authenticate with ECR, couldn't get docker credential helper to work
https://github.com/awslabs/amazon-ecr-credential-helper/issues/117

Setting aws-node to pull image only if image is not present found success

### Procedure to create a privte EKS cluster (by hand)

1. Create a VPC with only private subnets
1. Create VPC endpoints for dkr.ecr, ecr, ec2, s3
1. Provide a web proxy for the EKS service API
1. Create an EKS cluster in the private VPC
1. Edit the aws-node daemonset to only pull images if not present
```bash
kubectl edit ds/aws-node -n kube-system
```
1. Deploy the CFN template, specifying proxy url and security group granting access to VPC endpoints
1. Add the worker instance role to the authentiation config map for the cluster
```bash
kubectl apply -f aws-auth-cm.yaml
```
1. profit

**Note** EKS AMI list is at https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html

**Note** Instructions to grant worker nodes access to the cluster https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html

### Sample http-proxy.conf for worker node to work with HTTP proxy 
/etc/systemd/system/kubelet.service.d/http-proxy.conf
[Service]
Environment="https_proxy=http://vpce-001234f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="HTTPS_PROXY=http://vpce-001234f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="http_proxy=http://vpce-001234f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="HTTP_PROXY=http://vpce-001234f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="NO_PROXY=169.254.169.254,2FDA1234AA4491779F1DF905AEFCB647.yl4.eu-west-1.eks.amazonaws.com,ec2.eu-west-1.amazonaws.com"

/usr/lib/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="https_proxy=http://vpce-001234f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="HTTPS_PROXY=http://vpce-001234f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="http_proxy=http://vpce-001234f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="HTTP_PROXY=http://vpce-001234f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="NO_PROXY=169.254.169.254,2FDA1234AA4491779F1DF905AEFCB647.yl4.eu-west-1.eks.amazonaws.com,ec2.eu-west-1.amazonaws.com"
