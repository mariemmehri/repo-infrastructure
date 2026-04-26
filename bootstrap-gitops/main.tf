# ============================================================================
# PHASE B - Bootstrap GitOps ArgoCD
#
# Cette stack est appliquee APRES la stack infra (terraform-todo).
# Objectif: creer l'application racine ArgoCD quand le CRD Application
# est deja enregistre par le chart ArgoCD.
# ============================================================================

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
        repoURL        = var.config_repo_url
        targetRevision = var.config_repo_revision
        path           = var.child_apps_path
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
}