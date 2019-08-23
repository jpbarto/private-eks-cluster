#!/bin/bash

CLUSTER_NAME='ire-eks-5'
REGION=eu-west-1
ROLE_ARN='arn:aws:iam::776347453069:role/EKSClusterRole'
SUBNETS='subnet-073ce7a65f7d38179,subnet-03847437c10d8ad9b,subnet-049e366af7f2c3c12'
SECURITY_GROUPS=sg-01b8a6379dc2d5722
WORKER_SECURITY_GROUPS=sg-01b8a6379dc2d5722
PROXY_URL=http://vpce-000256f5aa16f2228-aspopn6a.vpce-svc-062e1dc8165cd99df.eu-west-1.vpce.amazonaws.com:3128
KEY_PAIR=jasbarto-eu-west-1-sandbox.pem
VERSION='1.13'
AMI_ID=ami-0199284372364b02a
INSTANCE_TYPE=t3.medium
VPC_ID=vpc-074f02d7fd8128fcd

# aws cloudformation deploy <-- create a network in which to put the EKS cluster
# set SUBNETS, SECURITY_GROUPS, WORKER_SECURITY_GROUPS, VPC_ID appropriately

aws eks create-cluster \
    --name ${CLUSTER_NAME} \
    --role-arn ${ROLE_ARN} \
    --resources-vpc subnetIds=${SUBNETS},securityGroupIds=${SECURITY_GROUPS},endpointPublicAccess=false,endpointPrivateAccess=true \
    --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' \
    --kubernetes-version ${VERSION} \
    --region ${REGION}

# wait for the cluster to create
while [ $(aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.status' --output text --region ${REGION}) == "CREATING" ]
do
    echo Cluster ${CLUSTER_NAME} status: CREATING...
    sleep 60
done
echo Cluster ${CLUSTER_NAME} is ACTIVE

ENDPOINT=`aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.endpoint' --output text --region ${REGION}`
CERT_DATA=`aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.certificateAuthority.data' --output text --region ${REGION}`
TOKEN=`aws eks get-token --cluster-name ${CLUSTER_NAME} --region ${REGION} | jq -r '.status.token'`

echo ${CLUSTER_NAME} created
echo Endpoint ${ENDPOINT}
echo Certificate ${CERT_DATA}
echo Token ${TOKEN}
#!/bin/bash

aws cloudformation deploy \
    --template-file private-eks-worker-gen2.yaml \
    --stack-name ${CLUSTER_NAME}-worker \
    --capabilities CAPABILITY_IAM \
    --region ${REGION} \
    --parameter-overrides ClusterControlPlaneSecurityGroup=${SECURITY_GROUPS} \
    ClusterName=${CLUSTER_NAME} \
    KeyName=${KEY_PAIR} \
    NodeGroupName=${CLUSTER_NAME}-workers \
    NodeImageId=${AMI_ID} \
    NodeInstanceType=${INSTANCE_TYPE} \
    Subnets=${SUBNETS} \
    VpcId=${VPC_ID} \
    ClusterAPIEndpoint=${ENDPOINT} \
    ClusterCA=${CERT_DATA} \
    HttpsProxy=${PROXY_URL} \
    WorkerSecurityGroup=${WORKER_SECURITY_GROUPS} \
    UserToken=${TOKEN} \
    KubectlS3Location='s3://jasbarto-ireland-acm/kubectl'
