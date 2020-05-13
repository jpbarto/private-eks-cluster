# private-eks-cluster

CloudFormation template and associated shell script to create a VPC, an EKS cluster, and a worker node group all without internet connectivity.

## Overview

This collection of CloudFormation templates and Bash shell scripts will deploy an EKS cluster into a VPC with no Internet Gateway (IGW) or NAT Gateway attached.

To do this it will create:
- VPC
- VPC endpoints - for EC2, ECR, STS, AutoScaling, SSM
- VPC endpoint for Proxy - to an existing web proxy that you have already setup (not required but assumed you want to pull containers from DockerHub, GCR.io etc)
- IAM Permissions
- EKS Cluster - logging enabled and no public endpoint
- Auto-scaling Group for Node group - including bootstrap configuration for the proxy
- Fargate Profile for running containers on Fargate

Once completed you can (from within the VPC) communicate with your EKS cluster and see a list of running worker nodes.

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

 Once these values are set you can execute `launch_all.sh` and get a coffee. This will take approximately 10 min to create the vpc, endpoints, cluster, and worker nodes.

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

## Under the covers

Amazon EKS is managed upstream K8s. So all the requirements and capabilities of Kubernetes apply. This is to say that when you create an EKS cluster you are given either a private or public (or both) K8s master mode, managed for you as a service. When you create EC2 instances, hopefully as part of an auto scaling group, those nodes will need to be able to authenticate into the K8s master node and begun becoming managed by the master. The node runs the standard Kubelet and Docker daemon and will need the master's name and CA certificate. To do thus the Kubelet will query the EKS service or you can provide these as arguments to the bootstrap.sh. After connecting to the master it will receive instruction to launch daemon sets. To do this Kubelet and Docker will need to authenticate themselves into ECR wherethe DS images are probably kept. Please note that the 1.13 version of Kubelet is compatible with VPC endpoints for ECR but 1.11 and 1.12 will require a proxy server to reach ecr.REGION.amazonaws.com. After pulling down the daemon sets your cluster should be stable and ready for use. For details about configuring proxy servers for Kubelet etc please check out the source code.

## Development notes
### configure proxy for docker daemon
https://stackoverflow.com/questions/23111631/cannot-download-docker-images-behind-a-proxy

### authenticate with ECR
https://docs.aws.amazon.com/AmazonECR/latest/userguide/Registries.html#registry_auth

aws ecr get-login --region eu-west-1 --no-include-email
602401143452.dkr.ecr.eu-west-1.amazonaws.com/amazon-k8s-cni:v1.5.0
602401143452.dkr.ecr.eu-west-1.amazonaws.com/eks/kube-proxy:v1.11.5
602401143452.dkr.ecr.eu-west-1.amazonaws.com/eks/coredns:v1.1.3
602401143452.dkr.ecr.eu-west-1.amazonaws.com/eks/pause-amd64:3.1

Docker unable to authenticate with ECR, couldn't get docker credential helper to work
https://github.com/awslabs/amazon-ecr-credential-helper/issues/117

Setting aws-node to pull image only if image is not present found success

### Procedure

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
