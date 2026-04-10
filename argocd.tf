# =============================================================================
# ARGOCD — Installation + bootstrap GitOps sur AKS
#
# Ce fichier:
# 1) installe ArgoCD via Helm
# 2) crée l'Application racine (App-of-Apps) pour démarrer GitOps automatiquement
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

# ─── Bootstrap GitOps : Application racine ArgoCD ───────────────────────────
# Objectif : après `terraform apply`, ArgoCD commence automatiquement à
# synchroniser le repo de configuration sans action manuelle `kubectl apply`.
resource "kubernetes_manifest" "argocd_root_app" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "apps-root"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/mariemmehri/repo-config"
        targetRevision = "main"
        # On cible un sous-dossier dédié aux apps enfants pour éviter
        # l'auto-référence de l'Application racine.
        path = "apps/children"
        directory = {
          recurse = true
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd
  ]
}
