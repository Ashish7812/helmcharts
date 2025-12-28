
############################################
# Variables
############################################
variable "region" { type = string }
variable "eks_cluster_name" { type = string }

variable "publish_secret_name" {
  type        = string
  default     = "tf-remote-kubeconfig-secret"
  description = "Name of the kubeconfig Secret in the management cluster"
}

variable "publish_secret_namespace" {
  type        = string
  default     = "default"
  description = "Namespace for the kubeconfig Secret (must match HelmRelease namespace)"
}

variable "remote_target_namespace" {
  type        = string
  default     = "default"
  description = "Namespace on the remote cluster for Helm release/storage"
}