# ============================================================================
# PHASE B - Bootstrap GitOps ArgoCD
#
# Cette stack est appliquee APRES la stack infra (terraform-todo).
# Objectif: creer l'application racine ArgoCD quand le CRD Application
# est deja enregistre par le chart ArgoCD.
# ============================================================================
resource "kubernetes_manifest" "argocd_app_of_apps" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "app-of-apps"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_target_revision
        path           = var.gitops_path
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