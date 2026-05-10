
# resource "kubernetes_namespace_v1" "argocd" {
#   metadata {
#     name = "argocd"
#   }
# }

# resource "helm_release" "argocd" {
#   name       = "argocd"
#   repository = "https://argoproj.github.io/argo-helm"
#   chart      = "argo-cd"
#   version    = var.argocd_chart_version
#   namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

#   values = [
#     yamlencode({
#       server = {
#         service = {
#           type = "ClusterIP"
#         }
#       }
#     })
#   ]

#   timeout = 600

#   depends_on = [kubernetes_namespace_v1.argocd]
# }
# Pas de bloc provider ici.
# Les providers helm et kubernetes sont hérités du module parent
# (environments/staging) qui les configure avec exec { gcloud }.

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]

  timeout    = 600
  depends_on = [kubernetes_namespace_v1.argocd]
}
