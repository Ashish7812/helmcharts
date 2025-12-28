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

# The IAM principal used by the Terraform runner (IRSA role ARN, or IAM role/user ARN).
# This will be granted access to the EKS API via Access Entries.
variable "runner_principal_arn" {
  description = "IAM role/user ARN used by Terraform runner; will be authorized in EKS"
  type        = string
}

variable "publish_secret_name" {
  description = "Name of the kubeconfig Secret in the management cluster"
  type        = string
  default     = "tf-remote-kubeconfig-secret"
}

variable "publish_secret_namespace" {
  description = "Namespace for the kubeconfig Secret in the management cluster (must match HelmRelease namespace)"
  type        = string
  default     = "default"
}

variable "remote_target_namespace" {
  description = "Namespace on the remote cluster where Helm installs/releases are stored"
  type        = string
  default     = "default"
}