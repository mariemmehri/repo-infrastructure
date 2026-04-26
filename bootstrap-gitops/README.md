# Bootstrap GitOps

Cette stack crée l’`Application` racine Argo CD qui sert de point d’entrée pour la réconciliation GitOps.

## Objectif

La stack d’environnement installe Argo CD lui-même. Cette stack de bootstrap s’exécute ensuite et crée l’application `apps-root` une fois les CRD et le contrôleur Argo CD disponibles.

## Ce qu’elle crée

- Une `Application` Kubernetes nommée `apps-root` dans le namespace `argocd`.
- Une synchronisation automatisée avec suppression des ressources orphelines et auto-réparation activées.
- La découverte récursive des applications enfants depuis le dépôt de configuration GitOps.

## Entrées

| Variable               | Description                                        | Valeur par défaut                            |
| ---------------------- | -------------------------------------------------- | -------------------------------------------- |
| `resource_group_name`  | Groupe de ressources qui contient le cluster AKS   | obligatoire                                  |
| `cluster_name`         | Nom du cluster AKS existant                        | obligatoire                                  |
| `config_repo_url`      | URL Git du dépôt qui contient les manifests GitOps | `https://github.com/mariemmehri/repo-config` |
| `config_repo_revision` | Révision Git suivie par Argo CD                    | `main`                                       |
| `child_apps_path`      | Chemin du dossier des applications enfants         | `apps/children`                              |

## Utilisation

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## Préconditions

- L’environnement de staging doit déjà être déployé.
- Argo CD doit déjà être installé dans le cluster.
- Le dépôt GitOps référencé par `config_repo_url` doit exister et contenir la structure attendue pour les applications enfants.

## Notes

- L’application racine cible l’API Kubernetes interne du cluster à l’adresse `https://kubernetes.default.svc`.
- L’application est créée dans le namespace `argocd`, donc ce namespace doit exister avant d’exécuter cette stack.
- Si vous modifiez la structure du dépôt de configuration, ajustez `child_apps_path` en conséquence.
