# Documentation du projet d'infrastructure

## Présentation du projet et objectifs

Ce dépôt contient l'infrastructure Terraform d'une plateforme Azure destinée à héberger une application conteneurisée sur Kubernetes. L'objectif principal est de provisionner une base d'exécution propre, reproductible et maintenable, depuis zéro jusqu'à une instance fonctionnelle prête à recevoir des déploiements applicatifs.

Le projet est organisé autour de deux blocs logiques:

- une stack principale qui crée l'infrastructure Azure et installe la couche de gestion Kubernetes
- une seconde stack Terraform séparée pour éviter les dépendances de démarrage entre ressources Kubernetes et ressources de configuration

## Technologies utilisées

- Terraform
- Provider `azurerm`
- Provider `kubernetes`
- Provider `helm`
- Azure Kubernetes Service (AKS)
- Azure Container Registry (ACR)
- Azure Blob Storage pour le backend distant Terraform
- Azure CLI pour l'initialisation et les opérations d'administration

## Structure actuelle du projet

Le dépôt contient actuellement:

- `terraform-todo/`
  - stack principale d'infrastructure
  - module réutilisable `modules/azure-infra/`
  - configuration des providers, variables et outputs
  - ressource d'installation d'ArgoCD dans AKS
- `terraform-bootstrap-gitops/`
  - seconde stack Terraform séparée
  - ressource `Application` racine
  - providers dédiés
  - variables séparées
- fichiers de backend local par stack
  - `terraform-todo/backend.tf`
  - `terraform-bootstrap-gitops/backend.tf`
  - exemples locaux `backend.hcl.example`

On ne trouve pas de scripts shell métier dans le dépôt. Le projet repose surtout sur la structure Terraform et sur les fichiers de configuration `.tf`.

## Travail mis en place jusqu'à maintenant

À ce stade, le projet met déjà en place les éléments suivants:

- création du Resource Group Azure
- création d'un Azure Container Registry en SKU Basic
- création d'un cluster AKS avec identité managée système
- attribution du rôle `AcrPull` au kubelet identity d'AKS pour autoriser le pull d'images depuis ACR
- récupération automatique de la kubeconfig AKS côté Terraform
- installation d'ArgoCD dans le namespace `argocd`
- exposition du serveur ArgoCD en `ClusterIP` pour un accès local par port-forward
- sortie d'outputs utiles pour `kubectl`, l'accès à l'interface et la récupération du mot de passe admin
- mise en place d'un backend Terraform distant sur Azure Blob Storage

## Backend distant Azure Blob Storage

Le state Terraform est maintenant externalisé dans Azure Blob Storage au lieu d'être conservé dans un fichier local suivi par Git.

### Ce qui est dans le code

- `terraform-todo/backend.tf`
- `terraform-bootstrap-gitops/backend.tf`

Ces fichiers déclarent le backend `azurerm`.

### Ce qui est configuré localement

Chaque stack possède aussi un exemple de configuration locale:

- `terraform-todo/backend.hcl.example`
- `terraform-bootstrap-gitops/backend.hcl.example`

Tu peux copier le fichier exemple en `backend.hcl`, puis lancer `terraform init -backend-config=backend.hcl`.

### Étapes locales

1. Créer une fois le resource group, le storage account et le container Blob pour le state.
2. Se connecter à Azure avec `az login`.
3. Copier le fichier `backend.hcl.example` en `backend.hcl` dans la stack concernée.
4. Adapter `storage_account_name` et éventuellement `resource_group_name`.
5. Lancer `terraform init` dans le dossier de la stack.

### Exemple de configuration locale

```hcl
resource_group_name  = "rg-tfstate"
storage_account_name = "<storageaccountname>"
container_name       = "tfstate"
key                  = "terraform-todo.tfstate"
use_azuread_auth     = true
```

Pour la seconde stack, seule la valeur de `key` change avec `terraform-bootstrap-gitops.tfstate`.

## Architecture de l'infrastructure, step by step

### 1. Point de départ

Le point de départ est un workspace vide côté Azure. Aucun groupe de ressources, aucun cluster et aucun registre conteneur n'existent au départ.

### 2. Création du Resource Group

Terraform crée d'abord un Resource Group. Ce groupe sert de conteneur logique pour l'ensemble des ressources Azure du projet.

### 3. Création du registre d'images

Ensuite, Terraform crée un Azure Container Registry. Son rôle est de stocker les images Docker utilisées par les workloads du cluster.

### 4. Création du cluster AKS

Terraform crée ensuite un cluster Kubernetes managé sur Azure:

- nom du cluster configurable
- taille et nombre de nœuds paramétrables
- disque système configuré à 30 Go
- identité `SystemAssigned` pour simplifier la gestion des accès Azure

### 5. Liaison AKS vers ACR

Une fois le cluster créé, Terraform ajoute une attribution de rôle `AcrPull` sur le registre ACR.

Cette étape est essentielle car elle permet au nœud Kubernetes de télécharger les images privées stockées dans ACR sans mot de passe applicatif.

### 6. Récupération de la configuration du cluster

La stack Terraform lit ensuite la configuration du cluster AKS via `azurerm_kubernetes_cluster`.

Cette kubeconfig alimente les providers `kubernetes` et `helm`, afin que Terraform puisse créer des ressources directement dans le cluster.

### 7. Préparation de l'espace système Kubernetes

Terraform crée le namespace `argocd`.

Ce namespace isole les composants d'administration et évite de mélanger les ressources système avec les applications métiers.

### 8. Installation du service de gestion Kubernetes

Le chart Helm `argo-cd` est déployé dans le namespace `argocd`.

Le service serveur est volontairement configuré en `ClusterIP`, ce qui signifie:

- pas d'exposition publique par défaut
- pas de coût supplémentaire de type LoadBalancer
- accès prévu via `kubectl port-forward`

### 9. État final actuel de l'instance

À l'état actuel décrit par le code du dépôt, l'instance cible est composée de:

- un Resource Group Azure
- un cluster AKS opérationnel
- un Azure Container Registry
- une relation de confiance entre AKS et ACR via `AcrPull`
- un namespace système `argocd`
- le serveur ArgoCD installé dans le cluster
- un backend Terraform distant pour stocker les états

## Configuration serveurs, réseau, sécurité, services installés

### Serveurs

- un cluster AKS avec un node pool par défaut
- taille VM paramétrable via `node_vm_size`
- nombre de nœuds paramétrable via `node_count`

### Réseau

- le serveur ArgoCD n'est pas exposé en `LoadBalancer`
- l'accès se fait localement par port-forward
- le cluster reste accessible via les mécanismes standard AKS

### Sécurité

- identité managée système pour le cluster
- pas de secret ACR côté code applicatif
- rôle Azure RBAC `AcrPull` au lieu d'un mot de passe de registre
- backend Terraform distant dans Azure Blob Storage
- authentification du backend possible via Azure AD avec `use_azuread_auth = true`

### Services installés

- Azure Resource Group
- Azure Container Registry
- Azure Kubernetes Service
- namespace Kubernetes `argocd`
- Helm release `argo-cd`
- backend Terraform Azure Blob Storage

## Résultat final actuel sur l'instance

Le résultat obtenu jusqu'à présent est une base d'infrastructure Azure cohérente et reproductible:

- l'infrastructure est découpée en blocs Terraform séparés
- les ressources Azure sont centralisées dans un Resource Group
- le cluster AKS peut récupérer les images depuis ACR
- la couche d'administration Kubernetes est installée dans le cluster
- l'accès à l'interface se fait de manière contrôlée via port-forward
- les états Terraform sont centralisés dans Azure Blob Storage

En pratique, l'instance actuelle correspond à une plateforme prête à héberger des déploiements conteneurisés, avec une base d'administration déjà en place.

## Problèmes rencontrés et solutions

### Problème 1: risque de course au démarrage des ressources Kubernetes

Le problème principal a été le décalage entre la création du cluster et la disponibilité réelle des objets Kubernetes attendus par Terraform.

**Solution:** séparation du projet en deux stacks Terraform afin de découpler la création de l'infrastructure et les ressources Kubernetes plus sensibles au timing.

### Problème 2: exposition inutile du serveur d'administration

Exposer le serveur en `LoadBalancer` aurait créé une surface réseau plus large et un coût Azure supplémentaire.

**Solution:** service configuré en `ClusterIP` et accès local via `kubectl port-forward`.

### Problème 3: gestion locale du state Terraform

Un state local pose un risque de conflit, de perte de fichier et de collaboration difficile.

**Solution:** backend Azure Blob Storage distant avec authentification Azure AD.

### Problème 4: accès aux images du registre

Sans autorisation explicite, AKS ne peut pas toujours tirer les images stockées dans ACR.

**Solution:** attribution du rôle `AcrPull` au kubelet identity du cluster.

### Problème 5: configuration du provider Kubernetes/Helm

Les providers doivent disposer d'une kubeconfig valide après création du cluster.

**Solution:** récupération dynamique de la configuration du cluster depuis Azure avant l'exécution des ressources Kubernetes et Helm.

## Conclusion

Le projet a déjà franchi l'étape la plus importante: la base Azure est provisionnée proprement, les accès sont cadrés, le cluster est prêt, et l'administration Kubernetes est installée. La suite du travail pourra se concentrer sur l'ajout des déploiements applicatifs, sans devoir remettre en cause l'architecture d'infrastructure.
