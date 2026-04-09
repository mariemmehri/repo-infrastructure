# Namespace ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.azure_infra]
}

# Namespace dev (pour ton app)
resource "kubernetes_namespace" "dev" {
  metadata {
    name = "dev"
  }

  depends_on = [module.azure_infra]
}

# Installation ArgoCD via Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.3"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Désactive TLS interne pour simplifier (dev only)
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  # Valeurs importantes
  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    module.azure_infra
  ]

  timeout = 600
}