# Module GKE

Crée le cluster Kubernetes Google (GKE).

## Inputs

| Variable      | Description              | Défaut        |
| ------------- | ------------------------ | ------------- |
| cluster_name  | Nom du cluster           | requis        |
| project_id    | GCP Project ID           | requis        |
| region        | Région GCP               | requis        |
| environment   | Nom de l'env             | requis        |
| node_count    | Nombre de nodes          | 1             |
| node_vm_size  | Machine type GCP         | e2-standard-2 |
| vpc_name      | Nom du VPC               | requis        |
| gke_subnet_id | ID du subnet GKE         | requis        |
| acr_id        | ID Artifact Registry     | requis        |

## Outputs

| Output                     | Description          |
| -------------------------- | -------------------- |
| cluster_name               | Nom du cluster       |
| kube_host                  | API server URL       |
| kube_cluster_ca_certificate| CA du cluster        |