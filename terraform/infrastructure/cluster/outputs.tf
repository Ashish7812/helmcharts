# FILE: outputs.tf

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "The endpoint for your EKS Kubernetes API server."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with your cluster."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "eks_node_role_arn" {
  description = "The ARN of the IAM role assigned to the EKS worker nodes."
  value       = aws_iam_role.eks_node_role.arn
}
