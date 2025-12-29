# FILE: terraform/03-kubeconfig-builder/main.tf

terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"
    }
  }
}

provider "kubernetes" {
  # This provider only interacts with the management cluster
}

# --- STAGE 3: Read the intermediate secret from Stage 2 ---
data "kubernetes_secret" "intermediate_data" {
  metadata {
    name      = "tf-remote-raw-token-secret"
    namespace = var.publish_secret_namespace
  }
}

# --- Prepare all values in a locals block to satisfy the planner ---
locals {
  # The data source gives us the plain-text URL directly.
  cluster_endpoint = data.kubernetes_secret.intermediate_data.data["cluster_endpoint"]

  # The data source gives us the plain-text JWT token directly.
  sa_token = data.kubernetes_secret.intermediate_data.data["token_b64"]

  # The data source gives us the DECODED CA certificate. The Kubeconfig needs it
  # to be RE-ENCODED. We use nonsensitive() to allow this during the plan.
  cluster_ca_certificate_b64 = base64encode(nonsensitive(data.kubernetes_secret.intermediate_data.data["cluster_ca_certificate"]))
}


# --- Build and Publish Final Kubeconfig ---
# This resource now contains NO function calls, only direct variable substitutions.
resource "kubernetes_secret" "published_kubeconfig" {
  metadata {
    name      = var.publish_secret_name
    namespace = var.publish_secret_namespace
    labels = {
      "managed-by" = "terraform"
      "purpose"    = "flux-helmrelease-kubeconfig"
    }
  }
  type = "Opaque"
  data = {
    value = <<-YAML
      apiVersion: v1
      kind: Config
      clusters:
        - name: remote
          cluster:
            server: ${local.cluster_endpoint}
            certificate-authority-data: ${local.cluster_ca_certificate_b64}
      users:
        - name: flux-remote-helm
          user:
            token: ${local.sa_token}
      contexts:
        - name: remote
          context:
            cluster: remote
            user: flux-remote-helm
      current-context: remote
    YAML
  }
}
