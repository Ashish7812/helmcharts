# FILE: terraform/01-aws-permissions/main.tf

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

# This stage ONLY creates the AWS EKS Access Entry and its policy.
# It grants permission to the principal that will run the next stage.
resource "aws_eks_access_entry" "runner" {
  cluster_name  = var.eks_cluster_name
  principal_arn = var.runner_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "runner_admin" {
  cluster_name  = var.eks_cluster_name
  principal_arn = var.runner_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
