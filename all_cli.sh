#!/bin/bash
set -e

CLUSTER_NAME='fra-eks-5'
REGION=eu-central-1
HTTP_PROXY_ENDPOINT_SERVICE_NAME=com.amazonaws.vpce.eu-central-1.vpce-svc-036915ed05f9700df
KEY_PAIR=jasbarto-dev-fra
VERSION='1.13'
AMI_ID=ami-038bd8d3a2345061f
INSTANCE_TYPE=t3.medium

# aws cloudformation deploy <-- create a network in which to put the EKS cluster
# set SUBNETS, SECURITY_GROUPS, WORKER_SECURITY_GROUPS, VPC_ID appropriately
STACK_NAME=${CLUSTER_NAME}-vpc
aws cloudformation package \
    --s3-bucket jasbarto-dev-frankfurt-cloudformation \
    --output-template-file /tmp/packaged.yaml \
    --region ${REGION} \
    --template-file cloudformation/environment.yaml

aws cloudformation deploy \
    --template-file /tmp/packaged.yaml \
    --region ${REGION} \
    --stack-name ${STACK_NAME} \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides HttpProxyServiceName=${HTTP_PROXY_ENDPOINT_SERVICE_NAME} StackPrefix=${CLUSTER_NAME}

VPC_ID=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='VPCId'].OutputValue" --output text`
SUBNETS=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='Subnets'].OutputValue" --output text`
ROLE_ARN=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='MasterRoleArn'].OutputValue" --output text`
MASTER_SECURITY_GROUPS=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='MasterSecurityGroup'].OutputValue" --output text`
WORKER_SECURITY_GROUPS=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='EndpointClientSecurityGroup'].OutputValue" --output text`
PROXY_URL=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='HttpProxyUrl'].OutputValue" --output text`

aws eks create-cluster \
    --name ${CLUSTER_NAME} \
    --role-arn ${ROLE_ARN} \
    --resources-vpc subnetIds=${SUBNETS},securityGroupIds=${MASTER_SECURITY_GROUPS},endpointPublicAccess=false,endpointPrivateAccess=true \
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
    ClusterAPIEndpoint=${ENDPOINT} \
    ClusterCA=${CERT_DATA} \
    HttpsProxy=${PROXY_URL} \
    WorkerSecurityGroup=${WORKER_SECURITY_GROUPS} \
    UserToken=${TOKEN} \
    KubectlS3Location='s3://jasbarto-ireland-acm/kubectl'
