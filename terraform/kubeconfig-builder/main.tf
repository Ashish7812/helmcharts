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

# --- Build and Publish Final Kubeconfig ---
# This resource now correctly decodes all values from the intermediate secret.
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
            # DECODE NEEDED: The endpoint was base64 encoded when stored in the secret.
            server: ${base64decode(data.kubernetes_secret.intermediate_data.data["cluster_endpoint"])}
            # DECODE NEEDED: The CA data was also base64 encoded.
            certificate-authority-data: ${base64decode(data.kubernetes_secret.intermediate_data.data["cluster_ca_certificate"])}
      users:
        - name: flux-remote-helm
          user:
            # DECODE NEEDED: This line was the original source of the error, now fixed with nonsensitive().
            token: ${base64decode(nonsensitive(data.kubernetes_secret.intermediate_data.data["token_b64"]))}
      contexts:
        - name: remote
          context:
            cluster: remote
            user: flux-remote-helm
      current-context: remote
    YAML
  }
}
