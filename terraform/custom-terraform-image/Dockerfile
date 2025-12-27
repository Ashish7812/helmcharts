
# A known base for tf-controller runners (the "-base" variant expects you to add tools)
# See tf-controller docs for base tags. Here we pick a concrete version.
FROM ghcr.io/flux-iac/tf-runner:v0.16.0-rc.3-base

# Work as root while installing tools
USER root

# Ensure curl, unzip, CA certs are present (Debian/Ubuntu or Alpine fallback)
RUN set -eux; \
    (apt-get update && apt-get install -y --no-install-recommends curl unzip ca-certificates) \
    || (apk add --no-cache curl unzip ca-certificates)

# --- Terraform CLI (Linux amd64): pin to 1.14.3 ---
# Source: HashiCorp "Install Terraform" & releases (direct zip per platform/version)
# https://releases.hashicorp.com/terraform/1.14.3/terraform_1.14.3_linux_amd64.zip
ADD https://releases.hashicorp.com/terraform/1.14.3/terraform_1.14.3_linux_amd64.zip /tmp/terraform.zip
RUN set -eux; \
    unzip -q /tmp/terraform.zip -d /usr/local/bin/ && \
    rm /tmp/terraform.zip && \
    chmod +x /usr/local/bin/terraform
# (Terraform 1.14.3 is the latest stable as of Dec 17, 2025.) [4](https://developer.hashicorp.com/terraform/install)[5](https://releases.hashicorp.com/terraform/)

# --- kubectl (Linux amd64): download latest stable from official endpoint ---
# This uses the canonical dl.k8s.io stable.txt pattern from Kubernetes docs.
RUN set -eux; \
    curl -L -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x /usr/local/bin/kubectl
# (Install method per official docs.) [6](https://github.com/kubernetes/website/blob/main/content/en/docs/tasks/tools/install-kubectl-linux.md)[7](https://pwittrock.github.io/docs/tasks/tools/install-kubectl/)

# --- AWS CLI v2 (Linux x86_64): official installer ---
RUN set -eux; \
    curl -L "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip
# (Install steps per AWS CLI v2 docs.) [8](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

# Switch back to non-root (runner user expected by tf-controller images)
USER 65532:65532
