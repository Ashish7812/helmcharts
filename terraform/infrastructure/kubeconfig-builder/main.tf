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
# The .data map from this data source provides plain-text values for the token
# and endpoint, and a correctly single-encoded base64 string for the CA cert.
data "kubernetes_secret" "intermediate_data" {
  metadata {
    name      = "tf-remote-raw-token-secret"
    namespace = var.publish_secret_namespace
  }
}

# --- Build and Publish Final Kubeconfig ---
# This version is the simplest and correct one. It uses the values from the
# data source directly, as they are already in the correct format.
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
            # Correct: Use the plain-text URL directly.
            server: ${data.kubernetes_secret.intermediate_data.data["cluster_endpoint"]}
            # Correct: Use the single-encoded CA data directly.
            certificate-authority-data: ${data.kubernetes_secret.intermediate_data.data["cluster_ca_certificate"]}
      users:
        - name: flux-remote-helm
          user:
            # Correct: Use the plain-text token directly.
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
