# FILE: kubeconfig.tpl
apiVersion: v1
kind: Config
clusters:
  - name: remote
    cluster:
      server: ${cluster_endpoint}
      certificate-authority-data: ${cluster_ca_data}
users:
  - name: flux-remote-helm
    user:
      token: ${sa_token}
contexts:
  - name: remote
    context:
      cluster: remote
      user: flux-remote-helm
current-context: remote
