data "aws_eks_cluster" "cluster" {
  name = module.eks_cluster.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks_cluster.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.9"
}

resource "aws_kms_key" "eks" {
  description = "EKS Secret Encryption Key"
}

module "eks_cluster" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = var.eks_cluster_name
  cluster_version = "1.16"

  cluster_endpoint_public_access = true
  cluster_endpoint_private_access = true

  enable_irsa = true

  cluster_enabled_log_types = ["api","audit","authenticator","controllerManager","scheduler"]

  cluster_encryption_config = [
    {
      provider_key_arn = aws_kms_key.eks.arn
      resources        = ["secrets"]
    }
  ]

  subnets         = module.eks_vpc.private_subnets
  vpc_id          = module.eks_vpc.vpc_id

  worker_groups = [
    {
      instance_type = "t3.large"
      asg_min_size = 0
      asg_desired_capacity = 0
      asg_max_size  = 5
    }
  ]

  tags = {
    Terraform = "true"
    Environment = "dev"
    Project = "eks"
  }
}