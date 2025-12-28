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