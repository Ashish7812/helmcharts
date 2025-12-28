
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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

############################################
# Providers
############################################

provider "aws" {
  region = var.region
}

# Remote (target) cluster provider uses the exec-auth kubeconfig we generate
provider "kubernetes" {
  alias       = "remote"
  config_path = var.exec_kubeconfig_relpath
}

# Management cluster provider:
# In tf-controller, leaving config unset lets it use in-cluster ServiceAccount automatically. [8](https://devopscube.com/kubernetes-api-access-service-account/)
provider "kubernetes" {
  alias = "mgmt"
}

############################################
# 1) Generate EKS exec-auth kubeconfig (in-runner)  [1](https://opentofu.org/docs/language/settings/backends/configuration/)
############################################

resource "null_resource" "generate_kubeconfig" {
  triggers = {
    region          = var.region
    eks_cluster     = var.eks_cluster_name
    kubeconfig_path = var.exec_kubeconfig_relpath
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-CMD
      set -euo pipefail
      aws eks update-kubeconfig \
        --region '${var.region}' \
        --name '${var.eks_cluster_name}' \
        --kubeconfig '${var.exec_kubeconfig_relpath}' \
        --alias '${var.eks_cluster_name}'
    CMD
  }
}

############################################
# 2) Read EKS endpoint & CA (for final kubeconfig)  [9](https://github.com/mrphuongbn/tf-controller)
############################################

data "aws_eks_cluster" "target" {
  name = var.eks_cluster_name
}

############################################
# 3) Remote cluster: SA + RBAC (WIDE ACCESS)
############################################

resource "kubernetes_service_account" "flux_remote_helm" {
  provider = kubernetes.remote

  metadata {
    name      = "flux-remote-helm"
    namespace = var.remote_target_namespace
  }

  depends_on = [null_resource.generate_kubeconfig]
}

# --- WIDE CLUSTER ROLE ---
resource "kubernetes_cluster_role" "flux_remote_helm_role" {
  provider = kubernetes.remote

  metadata {
    name = "flux-remote-helm-role"
  }

  # Full access to all API groups/resources (use cautiously)
  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  # Access non-resource URLs on the API server (optional but often useful)
  rule {
    non_resource_urls = ["*"]
    verbs             = ["*"]
  }

  depends_on = [null_resource.generate_kubeconfig]
}

resource "kubernetes_cluster_role_binding" "flux_remote_helm_binding" {
  provider = kubernetes.remote

  metadata {
    name = "flux-remote-helm-binding"
  }

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

  depends_on = [kubernetes_cluster_role.flux_remote_helm_role]
}


############################################
# 4) Remote cluster: SA token Secret (wait until token is populated)
#    Kubernetes 1.24+ requires manual SA token; provider can wait for token. [2](https://www.harness.io/blog/gitops-your-terraform-or-opentofu)[3](https://developer.hashicorp.com/terraform/language/backend)
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

  depends_on = [kubernetes_cluster_role_binding.flux_remote_helm_binding]
}

############################################
# 5) Build static-token kubeconfig (no exec)
############################################

locals {
  remote_sa_token = base64decode(kubernetes_secret.flux_remote_sa_token.data["token"])
  kubeconfig      = <<-YAML
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

############################################
# 6) Management cluster: publish kubeconfig Secret for Flux HelmRelease
#    Secret must be in same namespace; data key defaults to "value". [4](https://flux-iac.github.io/tofu-controller/References/terraform/)
############################################

resource "kubernetes_secret" "published_kubeconfig" {
  provider = kubernetes.mgmt

  metadata {
    name      = var.publish_secret_name
    namespace = var.publish_secret_namespace
    labels = {
      "managed-by" = "terraform"
      "purpose"    = "flux-helmrelease-kubeconfig"
    }
  }

  data = { value = local.kubeconfig }

  type = "Opaque"
}

############################################
# Outputs (sanity checks)
############################################

output "exec_kubeconfig_written" {
  value       = var.exec_kubeconfig_relpath
  description = "Path inside runner where exec-auth kubeconfig was written"
}

output "published_secret" {
  value       = "${var.publish_secret_namespace}/${var.publish_secret_name}"
  description = "Kubeconfig Secret published for Flux HelmRelease"
}

output "remote_sa_token_preview" {
  value       = substr(local.remote_sa_token, 0, 20)
  description = "First 20 chars of the generated SA token"
  sensitive   = true
}
