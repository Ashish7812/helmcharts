############################################
# Variables
############################################
variable "region" {
  description = "AWS region of the target EKS cluster"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the target EKS cluster"
  type        = string
}

############################################
# Define the principal ARN for clarity
############################################
# Using the EKS Node Role as the principal.
# WARNING: This is not a security best practice. See notes below.
variable "runner_principal_arn" {
  description = "The IAM principal ARN that runs Terraform. Using the Node Role for a quick fix."
  default     = "arn:aws:iam::810918108393:role/eksctl-k8-simulation-nodegroup-def-NodeInstanceRole-WrSOfoyc7m3b"
}