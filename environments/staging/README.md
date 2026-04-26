# Environnement de staging

Cette stack provisionne l’infrastructure Azure utilisée par le déploiement de staging.

## Objectif

Elle crée le groupe de ressources de l’environnement, le réseau, Azure Container Registry, le cluster AKS et l’installation d’Argo CD pour la plateforme de staging.

## Ce qu’elle crée

- Un groupe de ressources de staging.
- Un réseau virtuel et un subnet AKS.
- Un Azure Container Registry pour les images conteneurisées.
- Un cluster AKS connecté au subnet.
- Une installation Argo CD dans le cluster.

## Fichiers de cette stack

- `main.tf` relie le groupe de ressources Azure et les modules.
- `variables.tf` définit les valeurs propres à l’environnement.
- `outputs.tf` expose les noms et identifiants clés utilisés par les étapes suivantes.

## Entrées

| Variable              | Description                               | Valeur par défaut  |
| --------------------- | ----------------------------------------- | ------------------ |
| `location`            | Région Azure de l’environnement           | `swedencentral`    |
| `resource_group_name` | Groupe de ressources créé pour le staging | obligatoire        |
| `cluster_name`        | Nom du cluster AKS                        | obligatoire        |
| `node_count`          | Nombre de nœuds par défaut                | `1`                |
| `node_vm_size`        | Taille de VM pour le pool de nœuds AKS    | `Standard_D2as_v5` |
| `acr_name`            | Nom du registre Azure Container Registry  | obligatoire        |

## Utilisation

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## Sorties

La stack expose actuellement les noms et détails de connexion importants via les sorties de ses modules. Utilisez les sorties AKS lorsque vous avez besoin des identifiants du cluster pour de l’automatisation ultérieure.

## Notes

- L’environnement attend la configuration backend créée par `backend-config/`.
- Le module réseau est créé avant AKS afin que le cluster dispose d’un subnet dédié.
- Argo CD est installé après AKS pour que l’API du cluster soit disponible pour le provider Helm.
