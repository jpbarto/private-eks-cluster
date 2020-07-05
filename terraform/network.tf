data "aws_region" "current" {}

module "eks_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "eks-vpc"
  cidr = "10.1.0.0/16"

  azs             = ["${data.aws_region.current.name}a", "${data.aws_region.current.name}b", "${data.aws_region.current.name}c"]
  private_subnets = ["10.1.10.0/24", "10.1.20.0/24", "10.1.30.0/24"]
  public_subnets  = ["10.1.110.0/24", "10.1.120.0/24", "10.1.130.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false
  one_nat_gateway_per_az = true

  tags = {
    Terraform = "true"
    Environment = "dev"
    Project = "eks"
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "eks_secondary_cidr" {
  vpc_id     = module.eks_vpc.vpc_id
  cidr_block = "100.64.0.0/16"
}

resource "aws_subnet" "eks_ext_subnet_1" {
  vpc_id     = aws_vpc_ipv4_cidr_block_association.eks_secondary_cidr.vpc_id
  cidr_block = "100.64.10.0/24"
  availability_zone = "${data.aws_region.current.name}a"
  tags = {
    Terraform = "true"
    Environment = "dev"
    Project = "eks"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = module.eks_cluster.cluster_id
    "kubernetes.io/cluster/${module.eks_cluster.cluster_id}" = "shared"
    "kubernetes.io/role/elb" = 1
  }
}

resource "aws_subnet" "eks_ext_subnet_2" {
  vpc_id     = aws_vpc_ipv4_cidr_block_association.eks_secondary_cidr.vpc_id
  cidr_block = "100.64.20.0/24"
  availability_zone = "${data.aws_region.current.name}b"
  tags = {
    Terraform = "true"
    Environment = "dev"
    Project = "eks"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = module.eks_cluster.cluster_id
    "kubernetes.io/cluster/${module.eks_cluster.cluster_id}" = "shared"
    "kubernetes.io/role/elb" = 1
  }
}

resource "aws_subnet" "eks_ext_subnet_3" {
  vpc_id     = aws_vpc_ipv4_cidr_block_association.eks_secondary_cidr.vpc_id
  cidr_block = "100.64.30.0/24"
  availability_zone = "${data.aws_region.current.name}c"
  tags = {
    Terraform = "true"
    Environment = "dev"
    Project = "eks"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = module.eks_cluster.cluster_id
    "kubernetes.io/cluster/${module.eks_cluster.cluster_id}" = "shared"
    "kubernetes.io/role/elb" = 1
  }
}