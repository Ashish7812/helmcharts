# FILE: variables.tf

variable "aws_region" {
  description = "The AWS region where all resources will be created."
  type        = string
  default     = "eu-south-1"
}

variable "cluster_name" {
  description = "A unique name for the EKS cluster. This will be used extensively for tagging resources."
  type        = string
  default     = "my-prod-cluster"
}

variable "vpc_cidr_block" {
  description = "The base CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "A list of Availability Zones to deploy the subnets into for high availability."
  type        = list(string)
  # It is strongly recommended to use at least 3 AZs for production.
  default     = ["eu-south-1a", "eu-south-1b", "eu-south-1c"]
}
