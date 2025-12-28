terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.29" }
    local = { source = "hashicorp/local", version = "~> 2.4" }
  }
}


############################################
# Providers
############################################
provider "aws" {
  region = var.region
}

# Read cluster endpoint & CA, and get an IAM-auth token to access the new cluster
data "aws_eks_cluster" "target" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "target" {
  name = var.eks_cluster_name
}

# Remote (target) Kubernetes provider: configured directly from AWS datasources
provider "kubernetes" {
  alias = "remote"
  host  = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(
    data.aws_eks_cluster.target.certificate_authority[0].data
  )
  token = data.aws_eks_cluster_auth.target.token
}

# Management cluster provider: where we publish the kubeconfig Secret for Flux
provider "kubernetes" {
  alias       = "mgmt"
}

############################################
# Remote cluster: ServiceAccount + RBAC
############################################
resource "kubernetes_service_account" "flux_remote_helm" {
  provider = kubernetes.remote
  metadata {
    name      = "flux-remote-helm"
    namespace = var.remote_target_namespace
  }
}

# Broad access to simplify bootstrap; tighten to least-privilege later.
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
}

############################################
# Remote cluster: SA token Secret (wait until populated)
# K8s v1.24+: tokens are not auto-created; create & wait
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
  wait_for_service_account_token = true
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

# Optional: write kubeconfig to a local file for debugging
resource "local_file" "remote_token_kubeconfig" {
  content  = local.kubeconfig
  filename = "./remote-token-kubeconfig.yaml"
}

############################################
# Management cluster: publish kubeconfig Secret for Flux HelmRelease
# Flux expects key "value" by default.
############################################
resource "kubernetes_secret" "published_kubeconfig" {
  provider = kubernetes.mgmt

  metadata {
    name      = var.publish_secret_name
    namespace = var.publish_secret_namespace
    labels = { "managed-by" = "terraform", "purpose" = "flux-helmrelease-kubeconfig" }
  }

  data = { value = local.kubeconfig }
  type = "Opaque"
}

############################################
# Outputs
############################################
output "published_secret" {
  value       = "${var.publish_secret_namespace}/${var.publish_secret_name}"
  description = "Kubeconfig Secret for Flux HelmRelease (key: value)"
}

output "remote_sa_token_preview" {
  value       = substr(local.remote_sa_token, 0, 24)
  description = "First 24 chars of the SA token"
  sensitive   = true
}

output "remote_kubeconfig_file" {
  value       = local_file.remote_token_kubeconfig.filename
  description = "Local copy of the token-based kubeconfig (debug)"
}
