#!/usr/bin/env bash

CLUSTER_NAME='private-eks-cluster'
REGION=us-west-2
HTTP_PROXY_ENDPOINT_SERVICE_NAME=com.amazonaws.vpce.us-west-2.vpce-svc-099d440360d6c276e
KEY_PAIR=my-ec2-keypair
VERSION='1.14'
AMI_ID=ami-05d586e6f773f6abf
INSTANCE_TYPE=t3.xlarge
S3_STAGING_LOCATION=s3-bucket-of-cloudformation
ENABLE_PUBLIC_ACCESS=false
