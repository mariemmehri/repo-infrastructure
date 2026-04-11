# =============================================================================
# PHASE A — Installation ArgoCD sur AKS
#
# Cette stack gere uniquement l'infrastructure ArgoCD (namespace + helm chart).
# Le bootstrap GitOps (Application apps-root) est volontairement deplace
# dans une stack separee: terraform-bootstrap-gitops.
#
# Pourquoi: eviter la course sur le CRD Application (
# argoproj.io/v1alpha1) qui peut ne pas etre pret immediatement apres Helm.
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
