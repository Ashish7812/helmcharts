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
# The .data map from this data source contains plain-text, already-decoded values.
data "kubernetes_secret" "intermediate_data" {
  metadata {
    name      = "tf-remote-raw-token-secret"
    namespace = var.publish_secret_namespace
  }
}

# --- Build and Publish Final Kubeconfig ---
# This version uses the plain-text values from the data source directly.
# No base64decode calls are needed.
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
            # This is the plain URL, used directly.
            server: ${data.kubernetes_secret.intermediate_data.data["cluster_endpoint"]}
            # This is the base64-encoded CA certificate, used directly.
            certificate-authority-data: ${data.kubernetes_secret.intermediate_data.data["cluster_ca_certificate"]}
      users:
        - name: flux-remote-helm
          user:
            # This is the plain JWT token, used directly.
            token: ${data.kubernetes_secret.intermediate_data.data["token_b64"]}
      contexts:
        - name: remote
          context:
            cluster: remote
            user: flux-remote-helm
      current-context: remote
    YAML
  }
}
