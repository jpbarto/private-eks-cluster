variable "target_region" {
    type = string
    description = "AWS region code in which to deploy EKS cluster"
    default = "eu-central-1"
}

variable "eks_cluster_name" {
    type = string
    description = "Name of the EKS cluster"
}