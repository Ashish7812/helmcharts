# FILE: terraform/02-kubeconfig-builder/main.tf

terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.29" }
  }
}

provider "kubernetes" {
  # This provider only talks to the management cluster
}

# --- STAGE 2: Read the intermediate secret from Stage 1 ---
data "kubernetes_secret" "intermediate_data" {
  metadata {
    name      = "tf-remote-raw-token-secret"
    namespace = var.publish_secret_namespace
  }
}

# --- Build and Publish Final Kubeconfig ---
# This can now safely decode the values from the data source,
# because the data source reads a resource that is guaranteed to exist.
resource "kubernetes_secret" "published_kubeconfig" {
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
            server: ${data.kubernetes_secret.intermediate_data.data["cluster_endpoint"]}
            certificate-authority-data: ${data.kubernetes_secret.intermediate_data.data["cluster_ca_certificate"]}
      users:
        - name: flux-remote-helm
          user:
            token: ${base64decode(data.kubernetes_secret.intermediate_data.data["token_b64"])}
      contexts:
        - name: remote
          context:
            cluster: remote
            user: flux-remote-helm
      current-context: remote
    YAML
  }
}
