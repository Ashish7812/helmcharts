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
# The .data map from this data source provides plain-text, decoded values.
data "kubernetes_secret" "intermediate_data" {
  metadata {
    name      = "tf-remote-raw-token-secret"
    namespace = var.publish_secret_namespace
  }
}

# --- Build and Publish Final Kubeconfig ---
# This version now correctly decodes, encodes, and uses values as required.
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
            # Correct: The endpoint URL needs to be decoded from the secret's data.
            server: ${base64decode(data.kubernetes_secret.intermediate_data.data["cluster_endpoint"])}
            # Correct: The CA cert data must be re-encoded to be valid in the Kubeconfig.
            certificate-authority-data: ${base64encode(data.kubernetes_secret.intermediate_data.data["cluster_ca_certificate"])}
      users:
        - name: flux-remote-helm
          user:
            # Correct: The token is already decoded by the data source, so use it directly.
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
