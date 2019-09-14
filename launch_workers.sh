#!/usr/bin/env bash
set -e

source variables.sh

# aws cloudformation deploy <-- create a network in which to put the EKS cluster
# set SUBNETS, SECURITY_GROUPS, WORKER_SECURITY_GROUPS, VPC_ID appropriately
STACK_NAME=${CLUSTER_NAME}-vpc

VPC_ID=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue" --output text`
VPC_CIDR=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='VPCCIDR'].OutputValue" --output text`
SUBNETS=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='Subnets'].OutputValue" --output text`
ROLE_ARN=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='MasterRoleArn'].OutputValue" --output text`
MASTER_SECURITY_GROUPS=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='MasterSecurityGroup'].OutputValue" --output text`
WORKER_SECURITY_GROUPS=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='EndpointClientSecurityGroup'].OutputValue" --output text`
PROXY_URL=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='HttpProxyUrl'].OutputValue" --output text`

ENDPOINT=`aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.endpoint' --output text --region ${REGION}`
CERT_DATA=`aws eks describe-cluster --name ${CLUSTER_NAME} --query 'cluster.certificateAuthority.data' --output text --region ${REGION}`

echo Endpoint ${ENDPOINT}
echo Certificate ${CERT_DATA}
echo Token ${TOKEN}

echo Staging kubectl to S3
curl -sLO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
aws s3 cp kubectl s3://${S3_STAGING_LOCATION}/kubectl
rm kubectl

TOKEN=`aws eks get-token --cluster-name ${CLUSTER_NAME} --region ${REGION} | jq -r '.status.token'`

aws cloudformation deploy \
    --template-file cloudformation/eks-workers.yaml \
    --stack-name ${CLUSTER_NAME}-worker \
    --capabilities CAPABILITY_IAM \
    --region ${REGION} \
    --parameter-overrides ClusterControlPlaneSecurityGroup=${MASTER_SECURITY_GROUPS} \
    ClusterName=${CLUSTER_NAME} \
    KeyName=${KEY_PAIR} \
    NodeGroupName=${CLUSTER_NAME}-workers \
    NodeImageId=${AMI_ID} \
    NodeInstanceType=${INSTANCE_TYPE} \
    Subnets=${SUBNETS} \
    VpcId=${VPC_ID} \
    VpcCidr=${VPC_CIDR} \
    ClusterAPIEndpoint=${ENDPOINT} \
    ClusterCA=${CERT_DATA} \
    HttpsProxy=${PROXY_URL} \
    WorkerSecurityGroup=${WORKER_SECURITY_GROUPS} \
    UserToken=${TOKEN} \
    KubectlS3Location="s3://${S3_STAGING_LOCATION}/kubectl"
