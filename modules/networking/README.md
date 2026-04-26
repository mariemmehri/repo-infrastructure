# Module Networking

Crée le VNet et les subnets pour AKS.

## Inputs

| Variable            | Description     | Défaut      |
| ------------------- | --------------- | ----------- |
| resource_group_name | Nom du RG       | requis      |
| location            | Région Azure    | requis      |
| environment         | Nom de l'env    | requis      |
| vnet_address_space  | CIDR du VNet    | 10.0.0.0/16 |
| aks_subnet_prefix   | CIDR subnet AKS | 10.0.1.0/24 |

## Outputs

| Output        | Description      |
| ------------- | ---------------- |
| vnet_id       | ID du VNet       |
| aks_subnet_id | ID du subnet AKS |
