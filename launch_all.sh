#!/usr/bin/env bash
set -e

source variables.sh 

# Check S3 bucket exists, if not create it
if [[ $(aws s3 ls | grep ${S3_STAGING_LOCATION}) ]]; then
    echo "Using S3 bucket ${S3_STAGING_LOCATION} for cloudformation and kubectl binary"
else
    aws s3api create-bucket \
        --bucket ${S3_STAGING_LOCATION} \
        --create-bucket-configuration LocationConstraint=${REGION} \
        --region ${REGION}
    echo "Created S3 bucket ${S3_STAGING_LOCATION} for cloudformation and kubectl binary"
fi

# aws cloudformation deploy <-- create a network in which to put the EKS cluster
# set SUBNETS, SECURITY_GROUPS, WORKER_SECURITY_GROUPS, VPC_ID appropriately
STACK_NAME=${CLUSTER_NAME}-vpc
aws cloudformation package \
    --s3-bucket ${S3_STAGING_LOCATION} \
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
EKS_CLUSTER_KMS_ARN=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='MasterKeyArn'].OutputValue" --output text`
PROXY_URL=${HTTP_PROXY_ENDPOINT_SERVICE_NAME}
if [ "${HTTP_PROXY_ENDPOINT_SERVICE_NAME}" != "" ]
then
    PROXY_URL=`aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='HttpProxyUrl'].OutputValue" --output text`
fi

aws eks create-cluster \
    --name ${CLUSTER_NAME} \
    --role-arn ${ROLE_ARN} \
    --encryption-config resources=secrets,provider={keyArn=${EKS_CLUSTER_KMS_ARN}} \
    --resources-vpc subnetIds=${SUBNETS},securityGroupIds=${MASTER_SECURITY_GROUPS},endpointPublicAccess=${ENABLE_PUBLIC_ACCESS},endpointPrivateAccess=true \
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

ISSUER_URL=$(aws eks describe-cluster --name $CLUSTER_NAME --query cluster.identity.oidc.issuer --output text --region $REGION)
AWS_FINGERPRINT=9E99A48A9960B14926BB7F3B02E22DA2B0AB7280

aws iam create-open-id-connect-provider \
    --url $ISSUER_URL \
    --thumbprint-list $AWS_FINGERPRINT \
    --client-id-list sts.amazonaws.com
echo Registered OpenID Connect provider with IAM

# Update Kubeconfig with new cluster details
aws eks --region ${REGION} \
	update-kubeconfig \
	--name ${CLUSTER_NAME}

source launch_workers.sh