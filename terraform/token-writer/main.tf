# FILE: terraform/02-remote-resources/main.tf

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.29" }
    time       = { source = "hashicorp/time", version = "~> 0.9" }
  }
}

# --- Providers ---
provider "aws" { region = var.region }
data "aws_eks_cluster" "target" { name = var.eks_cluster_name }
data "aws_eks_cluster_auth" "target" { name = var.eks_cluster_name }
provider "kubernetes" {
  alias                  = "remote"
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.target.token
}
provider "kubernetes" { alias = "mgmt" }

# --- Delay ---
resource "time_sleep" "wait_for_auth_propagation" { create_duration = "15s" }

# --- Remote Cluster RBAC & Token Secret ---
resource "kubernetes_service_account" "flux_remote_helm" {
  provider   = kubernetes.remote
  metadata { name = "flux-remote-helm"; namespace = var.remote_target_namespace }
  depends_on = [time_sleep.wait_for_auth_propagation]
}
resource "kubernetes_cluster_role" "flux_remote_helm_role" {
  provider   = kubernetes.remote
  metadata { name = "flux-remote-helm-role" }
  rule { api_groups = ["*"]; resources = ["*"]; verbs = ["*"] }
  rule { non_resource_urls = ["*"]; verbs = ["*"] }
  depends_on = [time_sleep.wait_for_auth_propagation]
}
resource "kubernetes_cluster_role_binding" "flux_remote_helm_binding" {
  provider   = kubernetes.remote
  metadata { name = "flux-remote-helm-binding" }
  role_ref { api_group = "rbac.authorization.k8s.io"; kind = "ClusterRole"; name = kubernetes_cluster_role.flux_remote_helm_role.metadata[0].name }
  subject { kind = "ServiceAccount"; name = kubernetes_service_account.flux_remote_helm.metadata[0].name; namespace = var.remote_target_namespace }
}
resource "kubernetes_secret" "flux_remote_sa_token" {
  provider                       = kubernetes.remote
  metadata { name = "flux-remote-helm-token"; namespace = var.remote_target_namespace; annotations = { "kubernetes.io/service-account.name" = kubernetes_service_account.flux_remote_helm.metadata[0].name } }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
  depends_on                     = [kubernetes_cluster_role_binding.flux_remote_helm_binding]
}

# --- STAGE 2 FINAL SECRET ---
resource "kubernetes_secret" "intermediate_raw_token" {
  provider = kubernetes.mgmt
  metadata { name = "tf-remote-raw-token-secret"; namespace = var.publish_secret_namespace; labels = { "managed-by" = "terraform", "purpose" = "intermediate-token" } }
  type = "Opaque"
  data = {
    "token_b64"              = kubernetes_secret.flux_remote_sa_token.data["token"]
    "cluster_endpoint"       = data.aws_eks_cluster.target.endpoint
    "cluster_ca_certificate" = data.aws_eks_cluster.target.certificate_authority[0].data
  }
}
