# FILE: main.tf

terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# IAM Roles for EKS
# EKS requires specific IAM roles for the control plane and worker nodes.
# -----------------------------------------------------------------------------

# IAM Role for the EKS Cluster Control Plane
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-cluster-role"

  # Trust policy allowing the EKS service to assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach the required AWS-managed policy to the cluster role.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}


# IAM Role for the EKS Worker Nodes
resource "aws_iam_role" "eks_node_role" {
  name = "${var.cluster_name}-node-role"

  # Trust policy allowing EC2 instances (our nodes) to assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach required AWS-managed policies for the worker nodes.
# These policies allow nodes to connect to the cluster and manage networking and container registries.
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}
resource "aws_iam_role_policy_attachment" "ecr_read_only_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}


# -----------------------------------------------------------------------------
# EKS Cluster Control Plane
# This provisions the managed, highly available Kubernetes API server.
# -----------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  # Specify the VPC configuration using the inputs from our network stage.
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true # Can be set to false for fully private clusters
  }

  # Ensure the IAM role for the cluster is created before the cluster itself.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}


# -----------------------------------------------------------------------------
# EKS Managed Node Group
# This creates the EC2 instances that will serve as our worker nodes.
# They are placed in the private subnets for security.
# -----------------------------------------------------------------------------
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_group_instance_types

  # Scaling configuration for the node group.
  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  # Update settings for graceful node termination and updates.
  update_config {
    max_unavailable = 1
  }

  # Ensure the IAM role for the nodes is fully configured before creating the node group.
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only_policy,
  ]
}
