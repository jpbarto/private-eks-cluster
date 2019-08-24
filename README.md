# private-eks-cluster
CloudFormation template and associated shell script to create a VPC, an EKS cluster, and a worker node group all without internet connectivity.
# configure proxy for docker daemon
https://stackoverflow.com/questions/23111631/cannot-download-docker-images-behind-a-proxy

# authenticate with ECR
https://docs.aws.amazon.com/AmazonECR/latest/userguide/Registries.html#registry_auth

aws ecr get-login --region eu-west-1 --no-include-email
602401143452.dkr.ecr.eu-west-1.amazonaws.com/amazon-k8s-cni:v1.5.0
602401143452.dkr.ecr.eu-west-1.amazonaws.com/eks/kube-proxy:v1.11.5
602401143452.dkr.ecr.eu-west-1.amazonaws.com/eks/coredns:v1.1.3
602401143452.dkr.ecr.eu-west-1.amazonaws.com/eks/pause-amd64:3.1

Docker unable to authenitcate with ECR, couldn't get docker credential helper to work
https://github.com/awslabs/amazon-ecr-credential-helper/issues/117

Setting aws-node to pull image only if image is not present found success

## Procedure

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
Environment="https_proxy=http://vpce-000256f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"Environment="HTTPS_PROXY=http://vpce-000256f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"Environment="http_proxy=http://vpce-000256f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="HTTP_PROXY=http://vpce-000256f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="NO_PROXY=169.254.169.254,2FDA9E47AA4491779F1DF905AEFCB647.yl4.eu-west-1.eks.amazonaws.com,ec2.eu-west-1.amazonaws.com"

/usr/lib/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="https_proxy=http://vpce-000256f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"Environment="HTTPS_PROXY=http://vpce-000256f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"Environment="http_proxy=http://vpce-000256f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="HTTP_PROXY=http://vpce-000256f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128"
Environment="NO_PROXY=169.254.169.254,2FDA9E47AA4491779F1DF905AEFCB647.yl4.eu-west-1.eks.amazonaws.com,ec2.eu-west-1.amazonaws.com"
