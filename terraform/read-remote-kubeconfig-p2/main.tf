terraform {
  required_version = ">= 1.5"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.29" }
    local      = { source = "hashicorp/local", version = "~> 2.4" }
    time       = { source = "hashicorp/time", version = "~> 0.9" }
  }
}

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
  alias = "mgmt"
}

############################################
# Bootstrap authorization in EKS via Access Entries (AWS-side)
############################################
resource "aws_eks_access_entry" "runner" {
  cluster_name  = var.eks_cluster_name
  principal_arn = var.runner_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "runner_admin" {
  cluster_name  = var.eks_cluster_name
  principal_arn = var.runner_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

############################################
# Delay for EKS Permission Propagation
############################################
resource "time_sleep" "wait_for_eks_auth" {
  create_duration = "30s"
  depends_on = [
    aws_eks_access_policy_association.runner_admin
  ]
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
  depends_on = [
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
}

############################################
# Remote cluster: ServiceAccount Token Secret
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
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
  depends_on = [
    kubernetes_cluster_role_binding.flux_remote_helm_binding
  ]
}

############################################
# STAGE 1: Intermediate Secret for Raw Token
############################################
# This secret stores the *raw, base64-encoded* token.
# We do not decode it here, which allows the plan to succeed.
resource "kubernetes_secret" "intermediate_raw_token" {
  provider = kubernetes.mgmt
  metadata {
    name      = "${var.publish_secret_name}-raw-token" # Give it a temporary name
    namespace = var.publish_secret_namespace
    labels    = { "managed-by" = "terraform", "purpose" = "intermediate-token" }
  }
  type = "Opaque"
  data = {
    # Just pass the raw base64 string. No functions are called.
    "token_b64" = kubernetes_secret.flux_remote_sa_token.data["token"]
  }
}

############################################
# STAGE 2: Final Kubeconfig Secret
############################################
# This final secret depends on the intermediate secret.
# Now it can safely decode the value, as the dependency will be fully
# created during the apply phase before this resource is processed.
resource "kubernetes_secret" "published_kubeconfig" {
  provider = kubernetes.mgmt
  metadata {
    name      = var.publish_secret_name
    namespace = var.publish_secret_namespace
    labels    = { "managed-by" = "terraform", "purpose" = "flux-helmrelease-kubeconfig" }
  }
  type = "Opaque"

  data = {
    value = <<-YAML
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
            token: ${base64decode(kubernetes_secret.intermediate_raw_token.data["token_b64"])}
      contexts:
        - name: remote
          context:
            cluster: remote
            user: flux-remote-helm
      current-context: remote
    YAML
  }
}

############################################
# Optional: write kubeconfig locally (for debugging)
############################################
resource "local_file" "remote_token_kubeconfig" {
  content  = kubernetes_secret.published_kubeconfig.data["value"]
  filename = "./remote-token-kubeconfig.yaml"
}

############################################
# Outputs
############################################
output "published_secret" {
  value       = "${var.publish_secret_namespace}/${var.publish_secret_name}"
  description = "Kubeconfig Secret for Flux HelmRelease (data key: value)"
}

output "remote_kubeconfig_file" {
  value       = local_file.remote_token_kubeconfig.filename
  description = "Local copy of token-based kubeconfig (debug)"
}
