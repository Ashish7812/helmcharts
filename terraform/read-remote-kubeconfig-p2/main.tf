terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.29" }
    local = { source = "hashicorp/local", version = "~> 2.4" }
    time = { source = "hashicorp/time", version = "~> 0.9" } # <-- ADD THIS LINE
  }
}


############################################
# REMOVED: Import Block
# The 'import' block for Jenkins-User has been removed.
# Terraform will now create and manage the access entry for the Node Role.
############################################


############################################
# Providers
############################################
provider "aws" {
  region = var.region
}

data "aws_eks_cluster" "target" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "target" {
  name = var.eks_cluster_name
}

provider "kubernetes" {
  alias = "remote"
  host  = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(
    data.aws_eks_cluster.target.certificate_authority[0].data
  )
  token = data.aws_eks_cluster_auth.target.token
}

provider "kubernetes" {
  alias       = "mgmt"
}

# ADD THIS SLEEP RESOURCE to wait for EKS to propagate permissions
resource "time_sleep" "wait_for_eks_auth" {
  create_duration = "30s"

  depends_on = [
    aws_eks_access_policy_association.runner_admin
  ]
}

############################################
# Bootstrap authorization in EKS via Access Entries (AWS-side)
############################################
# MODIFIED: These resources now grant access to the Node Role ARN.
resource "aws_eks_access_entry" "runner" {
  cluster_name  = var.eks_cluster_name
  principal_arn = var.runner_principal_arn # Now using the Node Role ARN
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "runner_admin" {
  cluster_name  = var.eks_cluster_name
  principal_arn = var.runner_principal_arn # Now using the Node Role ARN
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

############################################
# Remote cluster: ServiceAccount + RBAC (No changes below this line)
############################################
resource "kubernetes_service_account" "flux_remote_helm" {
  provider = kubernetes.remote
  metadata {
    name      = "flux-remote-helm"
    namespace = var.remote_target_namespace
  }
  depends_on = [
    aws_eks_access_entry.runner,
    aws_eks_access_policy_association.runner_admin,
    time_sleep.wait_for_eks_auth
  ]
}

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
    aws_eks_access_policy_association.runner_admin,
    time_sleep.wait_for_eks_auth
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
# Remote cluster: SA token Secret
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
  depends_on = [
    kubernetes_cluster_role_binding.flux_remote_helm_binding
  ]
}

############################################
# Build self-contained token kubeconfig
############################################
############################################
# Build self-contained token kubeconfig (NO exec)
############################################
locals {
  # The .data["token"] is available only after apply. During plan, it's unknown,
  # causing base64decode to fail. We use try() to catch the plan-time error
  # and provide a placeholder, allowing the plan to succeed.
  # The actual token will be correctly decoded and used during the apply phase.
  remote_sa_token = try(base64decode(kubernetes_secret.flux_remote_sa_token.data["token"]), "token-is-known-after-apply")

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
  description = "Kubeconfig Secret for Flux HelmRelease (data key: value)"
}

output "remote_sa_token_preview" {
  value       = substr(base64decode(local.remote_sa_token), 0, 24)
  description = "First 24 chars of the SA token"
  sensitive   = true
}

output "remote_kubeconfig_file" {
  value       = local_file.remote_token_kubeconfig.filename
  description = "Local copy of token-based kubeconfig (debug)"
}
