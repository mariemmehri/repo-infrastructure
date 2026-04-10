# =============================================================================
# ARGOCD — (Installation) via Helm sur AKS
#
# Ce fichier fait UNIQUEMENT l'installation d'ArgoCD sur le cluster.
# La configuration de ce qu'ArgoCD surveille est dans argocd-app.tf
# =============================================================================

# ─── Namespace ArgoCD ─────────────────────────────────────────────────────────
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.azure_infra]
}


# ─── Installation ArgoCD via Helm ─────────────────────────────────────────────
# ArgoCD est de l'infrastructure → il va ici avec Terraform, PAS dans le Config Repo
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.3"      # version stable testée
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Désactive TLS interne du serveur ArgoCD
  # Nécessaire pour accéder à l'UI via port-forward sans certificat
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  # Type de service : ClusterIP = accessible uniquement via port-forward
  # Pas de LoadBalancer = pas de coût Azure supplémentaire
  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]

  # ArgoCD doit attendre que le cluster et le namespace existent
  depends_on = [
    kubernetes_namespace.argocd,
    module.azure_infra
  ]

  # ArgoCD prend du temps à démarrer (pods nombreux)
  timeout = 600
}
