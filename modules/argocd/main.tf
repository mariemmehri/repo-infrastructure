
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
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# reste du fichier inchangé...
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
