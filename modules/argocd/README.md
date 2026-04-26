# Module ArgoCD

Installe ArgoCD via Helm sur AKS.

## Inputs

| Variable                    | Description           |
| --------------------------- | --------------------- |
| kube_host                   | API server AKS        |
| kube_client_certificate     | Certificat client     |
| kube_client_key             | Clé client            |
| kube_cluster_ca_certificate | CA du cluster         |
| argocd_chart_version        | Version du chart Helm |

## Outputs

| Output    | Description      |
| --------- | ---------------- |
| namespace | Namespace ArgoCD |
