
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.29" }
    local = { source = "hashicorp/local", version = "~> 2.4" }
  }
}


############################################
# Adopt pre-existing EKS Access Entry
############################################
# This tells Terraform to manage the already-existing access entry
# for the Jenkins-User on cluster "k8-simulation-client"
import {
  to = aws_eks_access_entry.runner
  id = "k8-simulation-client:arn:aws:iam::810918108393:user/Jenkins-User"
}

############################################
# Providers
############################################
provider "aws" {
  region = var.region
}

# Read EKS endpoint & CA; obtain a short-lived IAM-auth token
data "aws_eks_cluster" "target" {
  name = var.eks_cluster_name
}
data "aws_eks_cluster_auth" "target" {
  name = var.eks_cluster_name
}
# Configure remote Kubernetes provider *directly* from AWS datasources
provider "kubernetes" {
  alias = "remote"
  host  = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(
    data.aws_eks_cluster.target.certificate_authority[0].data
  )
  token = data.aws_eks_cluster_auth.target.token
}
# Management cluster provider: publish kubeconfig Secret for Flux
provider "kubernetes" {
  alias       = "mgmt"
}

############################################
# Bootstrap authorization in EKS via Access Entries (AWS-side)
############################################
# Best-practice path for granting IAM principals access to EKS: Access Entries + Policies. [1](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)

resource "aws_eks_access_entry" "runner" {
  cluster_name  = var.eks_cluster_name
  principal_arn = var.runner_principal_arn
  type          = "STANDARD"

  # Do not set any "system:*" groups here.
  # kubernetes_groups = ["system:masters"]  # <-- DELETE this line
}

resource "aws_eks_access_policy_association" "runner_admin" {
  cluster_name  = var.eks_cluster_name
  principal_arn = var.runner_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
  # [7](https://registry.terraform.io/providers/-/aws/latest/docs/resources/eks_access_policy_association)[8](https://docs.aws.amazon.com/eks/latest/userguide/access-policies.html)

############################################
# Remote cluster: ServiceAccount + RBAC (after access is granted)
############################################
resource "kubernetes_service_account" "flux_remote_helm" {
  provider = kubernetes.remote
  metadata {
    name      = "flux-remote-helm"
    namespace = var.remote_target_namespace
  }

  depends_on = [
    aws_eks_access_entry.runner,
    aws_eks_access_policy_association.runner_admin
  ]
}

# Broad permissions to simplify bootstrap; tighten to least-privilege later.
resource "kubernetes_cluster_role" "flux_remote_helm_role" {
  provider = kubernetes.remote
  metadata { name = "flux-remote-helm-role" }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
  rule {
    non_resource_urls = ["*"]
    verbs             = ["*"]
  }

  depends_on = [
    aws_eks_access_entry.runner,
    aws_eks_access_policy_association.runner_admin
  ]
}

resource "kubernetes_cluster_role_binding" "flux_remote_helm_binding" {
  provider = kubernetes.remote
  metadata { name = "flux-remote-helm-binding" }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.flux_remote_helm_role.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.flux_remote_helm.metadata[0].name
    namespace = var.remote_target_namespace
  }

  depends_on = [
    kubernetes_cluster_role.flux_remote_helm_role
  ]
}

############################################
# Remote cluster: SA token Secret (wait until populated)
# K8s v1.24+: SA tokens aren't auto-created; create and wait. [4](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/)
############################################
resource "kubernetes_secret" "flux_remote_sa_token" {
  provider = kubernetes.remote
  metadata {
    name      = "flux-remote-helm-token"
    namespace = var.remote_target_namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.flux_remote_helm.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"

  # Provider waits until .data.token is available
  wait_for_service_account_token = true  # [3](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret)

  depends_on = [
    kubernetes_cluster_role_binding.flux_remote_helm_binding
  ]
}

############################################
# Build self-contained token kubeconfig (NO exec)
############################################
locals {
  remote_sa_token = base64decode(kubernetes_secret.flux_remote_sa_token.data["token"])

  kubeconfig = <<-YAML
    apiVersion: v1
    kind: Config
    clusters:
      - name: remote
        cluster:
          server: ${data.aws_eks_cluster.target.endpoint}
          certificate-authority-data: ${data.aws_eks_cluster.target.certificate_authority[0].data}
    users:
      - name: flux-remote-helm
        user:
          token: ${local.remote_sa_token}
    contexts:
      - name: remote
        context:
          cluster: remote
          user: flux-remote-helm
    current-context: remote
  YAML
}

# Optional: write kubeconfig locally (for debugging)
resource "local_file" "remote_token_kubeconfig" {
  content  = local.kubeconfig
  filename = "./remote-token-kubeconfig.yaml"
}

############################################
# Management cluster: publish kubeconfig Secret for Flux HelmRelease
# Flux expects the Secret data key default 'value'; same namespace as HelmRelease.
############################################
resource "kubernetes_secret" "published_kubeconfig" {
  provider = kubernetes.mgmt

  metadata {
    name      = var.publish_secret_name
    namespace = var.publish_secret_namespace
    labels = { "managed-by" = "terraform", "purpose" = "flux-helmrelease-kubeconfig" }
  }

  data = { value = local.kubeconfig }  # default key 'value' is recognized by Flux Helm Controller [5](https://docs.rs/flux-crds/latest/flux_crds/helm_toolkit_fluxcd_io/v2beta1/helm_release/struct.KubeConfig.html)
  type = "Opaque"
}

############################################
# Outputs
############################################
output "published_secret" {
  value       = "${var.publish_secret_namespace}/${var.publish_secret_name}"
  description = "Kubeconfig Secret for Flux HelmRelease (data key: value)"
}

output "remote_sa_token_preview" {
  value       = substr(local.remote_sa_token, 0, 24)
  description = "First 24 chars of the SA token"
  sensitive   = true
}

output "remote_kubeconfig_file" {
  value       = local_file.remote_token_kubeconfig.filename
  description = "Local copy of token-based kubeconfig (debug)"
}
