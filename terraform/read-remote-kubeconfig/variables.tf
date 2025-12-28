############################################
# Variables (adjust to your environment)
############################################

variable "region" {
  description = "AWS region of the target EKS cluster"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the target EKS cluster"
  type        = string
}

# Where to write the EKS exec-auth kubeconfig inside the runner (relative path)
variable "exec_kubeconfig_relpath" {
  description = "Relative path (inside runner workdir) for the kubeconfig produced by aws eks update-kubeconfig"
  type        = string
  default     = "./eks-exec-kubeconfig.yaml"
}

# Namespace on remote cluster (Helm storage/installation namespace)
variable "remote_target_namespace" {
  description = "Remote cluster namespace for Helm release/storage"
  type        = string
  default     = "default"
}

# Secret in management cluster where Flux HelmRelease will read kubeconfig
variable "publish_secret_name" {
  description = "Name of the kubeconfig Secret in the mgmt cluster"
  type        = string
  default     = "tf-remote-kubeconfig-secret"
}

variable "publish_secret_namespace" {
  description = "Namespace for the kubeconfig Secret in the mgmt cluster (must match HelmRelease namespace)"
  type        = string
  default     = "default"
}