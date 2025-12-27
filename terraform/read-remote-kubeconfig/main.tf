
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"
    }
  }
}

############################################
# Providers
############################################

# AWS provider: used only to read the EKS cluster endpoint and CA.
provider "aws" {
  region = var.region
}

# Kubernetes provider: points to the management/Flux cluster
# (the cluster where Flux's Helm Controller runs and where this Secret must live).
# If you run Terraform *in-cluster*, you can omit config_path and rely on in-cluster auth.
provider "kubernetes" {
  # Option A — local kubeconfig file:
  # config_path = "~/.kube/config"

  # Option B — explicit host & credentials (example):
  # host                   = var.mgmt_cluster_host
  # cluster_ca_certificate = base64decode(var.mgmt_cluster_ca)
  # token                  = var.mgmt_cluster_token
}

############################################
# Inputs
############################################

variable "region" {
  description = "AWS region where the target EKS cluster is deployed"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the target EKS cluster whose kubeconfig will be published as a Secret"
  type        = string
}

variable "secret_name" {
  description = "Name of the Kubernetes Secret to create (must be in same namespace as HelmRelease)"
  type        = string
  default     = "kubeconfig-target-eks"
}

variable "secret_namespace" {
  description = "Namespace in the management cluster where the Secret will be created (e.g., flux-system)"
  type        = string
  default     = "flux-system"
}

# Uncomment if you prefer provider host/token wiring instead of config_path
# variable "mgmt_cluster_host" { type = string }
# variable "mgmt_cluster_ca"   { type = string } # base64 cluster CA
# variable "mgmt_cluster_token" { type = string }

############################################
# Read EKS cluster attributes
############################################

data "aws_eks_cluster" "target" {
  name = var.eks_cluster_name
}

# Optional: if you need a token embedded (not usually needed when using exec):
# data "aws_eks_cluster_auth" "target" {
#   name = var.eks_cluster_name
# }

############################################
# Render kubeconfig (exec auth via aws CLI)
############################################

locals {
  kubeconfig = <<-YAML
    apiVersion: v1
    kind: Config
    clusters:
      - name: ${var.eks_cluster_name}
        cluster:
          server: ${data.aws_eks_cluster.target.endpoint}
          certificate-authority-data: ${data.aws_eks_cluster.target.certificate_authority[0].data}
    contexts:
      - name: ${var.eks_cluster_name}
        context:
          cluster: ${var.eks_cluster_name}
          user: ${var.eks_cluster_name}
    current-context: ${var.eks_cluster_name}
    users:
      - name: ${var.eks_cluster_name}
        user:
          exec:
            apiVersion: "client.authentication.k8s.io/v1beta1"
            command: "aws"
            args:
              - "eks"
              - "get-token"
              - "--cluster-name"
              - "${var.eks_cluster_name}"
              - "--region"
              - "${var.region}"
  YAML
}

############################################
# Publish the Secret (key must be "value")
############################################

resource "kubernetes_secret" "flux_remote_kubeconfig" {
  metadata {
    name      = var.secret_name
    namespace = var.secret_namespace
    labels = {
      "managed-by" = "terraform"
      "purpose"    = "flux-helmrelease-kubeconfig"
    }
  }

  # HelmRelease.spec.kubeConfig.secretRef defaults to key "value". [1](https://registry.terraform.io/providers/fluxcd/flux/latest)
  data = {
    value = local.kubeconfig
  }

  type = "Opaque"
}
