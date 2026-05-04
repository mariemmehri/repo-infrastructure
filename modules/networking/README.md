# Module Networking

Crée le VPC et le subnet pour GKE.

## Inputs

| Variable          | Description          | Défaut      |
| ----------------- | -------------------- | ----------- |
| project_id        | GCP Project ID       | requis      |
| region            | Région GCP           | requis      |
| environment       | Nom de l'env         | requis      |
| gke_subnet_prefix | CIDR subnet GKE      | 10.0.1.0/24 |

## Outputs

| Output       | Description       |
| ------------ | ----------------- |
| vpc_id       | ID du VPC         |
| gke_subnet_id| ID du subnet GKE  |
| vpc_name     | Nom du VPC        |