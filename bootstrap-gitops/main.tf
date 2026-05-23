# bootstrap-gitops/main.tf
# ============================================================
# PHASE B — Bootstrap GitOps ArgoCD (TOUT en une stack)
#
# Ordre d'exécution garanti par depends_on :
# namespace → helm ArgoCD → sleep 60s → vérif CRD → app-of-apps
# ============================================================

# ─── Step 1 : Namespace ArgoCD ────────────────────────────
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

# ─── Step 2 : Installation ArgoCD via Helm ────────────────
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm" 
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  wait          = true #Force Terraform/Helm à attendre que les ressources Kubernetes soient prêtes avant de terminer.
  wait_for_jobs = true #Attendre que les jobs (ex: argocd-redis-ha) soient terminés avant de considérer le déploiement réussi.
  timeout       = 600 #Augmente le timeout global pour les opérations Helm, utile si le cluster est lent ou si les ressources prennent du temps à se stabiliser.

  values = [
    yamlencode({
      server = {
        service = { type = "ClusterIP" }
      }
    })
  ]

  depends_on = [kubernetes_namespace_v1.argocd]
}

# # ─── Step 3 : Attendre enregistrement CRDs ────────────────
# # Helm wait=true garantit que les pods sont Running,
# # mais l'API server peut mettre quelques secondes
# # supplémentaires à indexer les nouveaux CRDs.
# resource "time_sleep" "wait_for_argocd_crds" {
#   depends_on      = [helm_release.argocd]
#   create_duration = "60s"
# }

# # ─── Step 4 : Vérifier que le CRD est bien enregistré ─────
# data "kubernetes_resource" "argocd_crd" {
#   api_version = "apiextensions.k8s.io/v1"
#   kind        = "CustomResourceDefinition"

#   metadata {
#     name = "applications.argoproj.io"
#   }

#   depends_on = [time_sleep.wait_for_argocd_crds]
# }

# ─── Step 5 : App of Apps ─────────────────────────────────
resource "kubernetes_manifest" "root_app" {

  # depends_on critique — les CRDs ArgoCD doivent exister
  # avant que Terraform essaie de créer une "Application"
  depends_on = [helm_release.argocd]  

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root-app"
      namespace = "argocd"
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url        # "https://github.com/mariemmehri/repo-config"
        targetRevision = var.gitops_target_revision  # "main"
        path           = "apps"                      # surveille ce dossier
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