# Module AKS

Crée le cluster Kubernetes Azure.

## Inputs

| Variable            | Description     | Défaut           |
| ------------------- | --------------- | ---------------- |
| cluster_name        | Nom du cluster  | requis           |
| resource_group_name | Nom du RG       | requis           |
| location            | Région Azure    | requis           |
| environment         | Nom de l'env    | requis           |
| node_count          | Nombre de nodes | 1                |
| node_vm_size        | Taille des VMs  | Standard_D2as_v5 |
| aks_subnet_id       | ID du subnet    | requis           |
| acr_id              | ID du registry  | requis           |

## Outputs

| Output       | Description    |
| ------------ | -------------- |
| cluster_name | Nom du cluster |
| kube_host    | API server URL |
