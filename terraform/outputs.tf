resource "local_file" "post_apply_script" {
    filename = "post_apply.sh"
    content = <<EOF
#!/bin/bash

# configure local kubectl
aws eks update-kubeconfig --name ${module.eks_cluster.cluster_id} --region ${data.aws_region.current.name}

# configure K8s for the secondary CIDR range
kubectl set env ds aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
kubectl set env ds aws-node -n kube-system ENI_CONFIG_LABEL_DEF=failure-domain.beta.kubernetes.io/zone
kubectl apply -f secondary_cidr_cni_config.yaml

# bring the worker nodes up
aws autoscaling set-desired-capacity \
    --auto-scaling-group-name ${module.eks_cluster.workers_asg_names[0]} \
    --desired-capacity 3 \
    --region ${data.aws_region.current.name}
EOF
}

resource "local_file" "secondary_cidr_cni_config" {
    filename = "secondary_cidr_cni_config.yaml"
    content = <<EOF
---
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
 name: ${data.aws_region.current.name}a
spec:
 subnet: ${aws_subnet.eks_ext_subnet_1.id}
 securityGroups:
 - ${module.eks_cluster.worker_security_group_id}

---
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
 name: ${data.aws_region.current.name}b
spec:
 subnet: ${aws_subnet.eks_ext_subnet_2.id}
 securityGroups:
 - ${module.eks_cluster.worker_security_group_id}

---
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata:
 name: ${data.aws_region.current.name}c
spec:
 subnet: ${aws_subnet.eks_ext_subnet_3.id}
 securityGroups:
 - ${module.eks_cluster.worker_security_group_id}

EOF
}