# FILE: variables.tf

variable "aws_region" {
  description = "The AWS region where the EKS cluster will be created."
  type        = string
  default     = "eu-south-1"
}

variable "cluster_name" {
  description = "The unique name of the EKS cluster. This MUST match the name used in the VPC stage."
  type        = string
  default     = "my-prod-cluster"
}

# --- VPC Inputs from the previous stage ---

variable "vpc_id" {
  description = "The ID of the VPC where the cluster will be deployed. (Output from the VPC stage)"
  type        = string
}

variable "private_subnet_ids" {
  description = "A list of private subnet IDs for the worker nodes. (Output from the VPC stage)"
  type        = list(string)
}

# --- EKS Node Group Configuration ---

variable "node_group_instance_types" {
  description = "A list of instance types to use for the worker nodes."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes for the autoscaling group."
  type        = number
  default     = 3
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes for the autoscaling group."
  type        = number
  default     = 1
}
