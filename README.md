# repo-infrastructure — Infrastructure as Code GCP

Infrastructure complète Google Cloud Platform pour l'environnement staging de la plateforme GitOps HR Portal (SIRH).  
Terraform 1.7.5 — Backend GCS — Workload Identity Federation — ArgoCD bootstrappé via GitHub Actions.

---

## Vue d'ensemble

Ce dépôt gère deux responsabilités distinctes avec des cycles de vie séparés :

| Phase | Répertoire | Responsabilité | State |
|-------|-----------|----------------|-------|
| **Pré-requis** (run once) | `backend-config/` | GCS state bucket + Workload Identity Federation | local |
| **Infra + GitOps** | `environments/staging/` | VPC, GKE, Artifact Registry, IAM + bootstrap ArgoCD | GCS `prefix=staging` |

---

## Structure

```
repo-infrastructure/
├── backend-config/              # Run once — crée le backend et le WIF
│   ├── main.tf                  # GCS bucket (state remote)
│   ├── wif.tf                   # Workload Identity Federation + 2 SA
│   ├── variables.tf
│   └── outputs.tf               # Valeurs à copier dans les secrets GitHub
│
├── environments/staging/        # Seul root Terraform actif
│   ├── main.tf                  # Orchestration des 4 modules
│   ├── providers.tf             # Provider Google + backend GCS
│   ├── variables.tf
│   ├── outputs.tf               # kubectl command, argocd_portforward...
│   └── moved.tf                 # Blocs moved — migration state IAM (supprimer après apply)
│
├── modules/                     # Modules Terraform réutilisables
│   ├── networking/              # VPC + subnet GKE
│   ├── gke/                     # Cluster GKE + node pool (pure compute)
│   ├── artifact_registry/       # Google Artifact Registry
│   └── iam/                     # Identités et IAM par environnement
│
└── .github/workflows/
    └── workflow-infra.yml       # Pipeline unique : infra + bootstrap ArgoCD
```

---

## Prérequis

- Terraform >= 1.7.0
- gcloud CLI configuré (`gcloud auth application-default login`)
- Projet GCP existant avec facturation activée
- tflint (optionnel, pour lint local)

---

## Étape 0 — Backend-config (une seule fois)

Ce répertoire crée l'infrastructure nécessaire pour que Terraform puisse stocker son state à distance. Il utilise un **state local** (bootstrapper du bootstrapper — problème poulet/œuf).

```bash
cd backend-config

cp terraform.tfvars.example terraform.tfvars  #Edit terraform.tfvars

terraform init
terraform apply
```

**Ce que cela crée :**
- Bucket GCS `tfstate-pfe-2026` avec versioning (7 versions max)
- Pool Workload Identity Federation `github-pool-v2`
- Provider WIF `github-provider` (trust tokens OIDC de GitHub Actions)
- Service Account `sa-terraform-ci` — droits projet : container.admin, compute.networkAdmin, artifactregistry.admin, storage.admin, iam.serviceAccountAdmin, resourcemanager.projectIamAdmin
- Service Account `sa-github-actions` — droits : artifactregistry.writer uniquement

> Note : `iam.serviceAccountUser` n'est **pas** accordé à `sa-terraform-ci` au niveau projet. Ce droit est accordé précisément par `modules/iam/` sur chaque SA GKE d'environnement — principe du moindre privilège.

**Après l'apply, copier les outputs dans les secrets GitHub :**

```bash
terraform output workload_identity_provider  # → WORKLOAD_IDENTITY_PROVIDER (infra)
terraform output terraform_ci_sa_email       # → SERVICE_ACCOUNT_EMAIL (infra)
terraform output github_actions_sa_email     # → GCP_SERVICE_ACCOUNT (app)
```

---

## Infra GCP — `environments/staging/`

Provisionne toutes les ressources cloud fondamentales via 4 modules.

```bash
cd environments/staging

cp terraform.tfvars.example terraform.tfvars  #Edit terraform.tfvars


terraform init \
  -backend-config="bucket=tfstate-pfe-2026" \
  -backend-config="prefix=staging"

terraform plan
terraform apply
```

**Ce que cela crée :**

| Ressource | Détail |
|-----------|--------|
| VPC | `vpc-staging-pfe`, auto-create-subnetworks=false |
| Subnet GKE | `subnet-gke-staging`, CIDR `10.0.1.0/24`, Private Google Access |
| Artifact Registry | `registry-staging-pfe`, format DOCKER, `europe-west1` |
| Service Account nodes | `sa-gke-staging-pfe` — 5 rôles : artifactregistry.reader, logging.logWriter, monitoring.metricWriter, monitoring.viewer, stackdriver.resourceMetadata.writer |
| GKE Cluster | VPC-native, Workload Identity activé, deletion_protection=false |
| Node Pool | 1 nœud `e2-standard-2`, spot=true, autoscaling 1-3, disk 30 Go |
| IAM Binding | `sa-terraform-ci` → serviceAccountUser sur `sa-gke-staging-pfe` (SA-level) |
| IAM Binding | `sa-terraform-ci` → serviceAccountUser sur le SA Compute Engine par défaut (requis par GKE au bootstrap) |

### Modules détaillés

#### `modules/networking/`

Crée un VPC personnalisé et un subnet dédié au GKE avec Private Google Access activé.

```hcl
google_compute_network.main       # VPC principal
google_compute_subnetwork.gke     # Subnet 10.0.1.0/24
```

#### `modules/artifact_registry/`

Crée un repository Docker dans Google Artifact Registry. L'URL complète de l'image :
```
europe-west1-docker.pkg.dev/<project>/<repo>/<image>:<tag>
```

#### `modules/iam/`

Couche d'identité par environnement. Trois responsabilités :

- Crée le Service Account GKE nodes `sa-gke-{env}-pfe`
- Lui accorde les 5 rôles minimum requis (logging, monitoring, artifactregistry, stackdriver)
- Accorde à `sa-terraform-ci` le droit `iam.serviceAccountUser` sur ce SA et sur le SA Compute Engine par défaut

```hcl
# Input  : project_id, environment, terraform_ci_sa_email, developer_group_email (nullable)
# Output : gke_nodes_sa_email → consommé par modules/gke
```

La variable `developer_group_email` est optionnelle (`default = null`). Quand elle est renseignée, un groupe Google obtient `container.clusterViewer`. Laisser à `null` en production.

#### `modules/gke/`

Reçoit `gke_nodes_sa_email` en input depuis `modules/iam/` — ne crée aucune identité.

- Désactive le node pool par défaut (géré séparément — bonne pratique)
- Active le mode VPC-native et Workload Identity
- Crée un node pool avec spot instances (économies de coût en staging)
- CKV_GCP_13 : auth par certificat client désactivée
- CKV_GCP_65 : NetworkPolicy Calico activée
- CKV_GCP_66 : Binary Authorization activée

---

## Bootstrap ArgoCD — job GitHub Actions

ArgoCD est installé par le job `bootstrap-argocd` dans `workflow-infra.yml`.

**Déclenchement :**
- Automatiquement après chaque `apply` réussi
- Manuellement via `workflow_dispatch` → action `bootstrap`
- Si l'infra est déjà à jour (plan exitcode=0), le job tourne quand même — le check `already_bootstrapped` le rend rapide (~5s) si ArgoCD est déjà installé

**Étapes du job :**

```
1. Check already_bootstrapped
   ├── Si ArgoCD namespace + root-app existent → skip (sauf action=bootstrap)
   └── Sinon → continuer

2. helm upgrade --install argocd argo/argo-cd
   --version 6.7.3 --wait --timeout 600s

3. kubectl wait crd/applications.argoproj.io --timeout=120s

4. kubectl wait pods -l argocd-server --timeout=300s

5. kubectl apply -f repo-config/apps/root-app.yaml
```


---

## Workflow GitHub Actions — `workflow-infra.yml`

**Un seul workflow** gère l'ensemble du cycle de vie : infra Terraform + bootstrap ArgoCD.

**Déclencheurs :**
- Push sur `main` (paths: `environments/**`, `modules/**`, `backend-config/**`)
- Pull Request vers `main`
- Schedule quotidien (13:30 UTC) — drift detection
- `workflow_dispatch` (plan | apply | destroy-staging | drift | bootstrap | unlock)

### Jobs

| Job | Dépendances | Condition | Description |
|-----|-------------|-----------|-------------|
| `validate` | — | Toujours | `terraform fmt -check`, `terraform validate` sur tous les modules |
| `lint` | validate | Toujours | `tflint --recursive` |
| `plan` | validate, lint | Sauf destroy | `terraform plan -detailed-exitcode`, commentaire PR, upload artifact |
| `apply` | plan | exitcode=2 + push | `terraform apply` + `kubectl wait nodes` — protégé par env `staging-apply` |
| `bootstrap-argocd` | plan, apply | Toujours (sauf PR, destroy) | Helm + kubectl ArgoCD install — idempotent |
| `detect-drift` | — | Schedule ou dispatch drift/plan | `terraform plan -refresh-only`, ouvre issue `terraform-drift` |
| `destroy` | — | dispatch destroy-staging | Cleanup ArgoCD → `terraform destroy` — protégé par env `staging-destroy` |
| `unlock` | — | dispatch unlock | Force-unlock état GCS bloqué (escape hatch) |

### Détail des jobs clés

**`plan`**
- Génère `tfplan.binary` + `tfplan.json`
- Commente automatiquement les PR avec un tableau Create/Update/Destroy
- Upload l'artifact plan (retention 1 jour) — `apply` le télécharge plutôt que de re-planifier

**`apply`**
- Protégé par GitHub Environment `staging-apply` (approbation manuelle recommandée)
- Télécharge l'artifact plan — garantit que ce qui est appliqué est exactement ce qui a été planifié
- Attend `kubectl wait nodes --all --timeout=300s` après apply

**`bootstrap-argocd`**
- Condition `always()` — tourne même si `apply` a été skippé (infra déjà à jour)
- Check `already_bootstrapped` via `kubectl get namespace argocd` — évite une réinstallation sur chaque push
- `action=bootstrap` force la réinstallation même si ArgoCD est présent

**`destroy`**
- Supprime d'abord le finalizer du `root-app` ArgoCD (évite le blocage cascade-delete)
- Uninstall ArgoCD via Helm
- Puis `terraform destroy`
- Protégé par GitHub Environment `staging-destroy`

**`unlock`**
- Lit le lock ID depuis GCS et appelle `terraform force-unlock`
- Escape hatch pour les locks orphelins après un apply annulé ou timeout

### Drift detection

```bash
terraform plan -refresh-only -detailed-exitcode
# exitcode=2 → ouvre une GitHub Issue avec label "terraform-drift"
# Ne crée pas de doublon si une issue ouverte existe déjà
```

---

## Authentification — Workload Identity Federation

GitHub Actions ne stocke aucune clé JSON. Le mécanisme :

```
GitHub Actions Runner
       │  génère un token OIDC signé par GitHub
       ▼
google-github-actions/auth@v2
       │  échange le token OIDC contre un token GCP (STS)
       ▼
GCP IAM (impersonation du SA)
       │  accès aux APIs GCP selon les rôles du SA
       ▼
terraform apply / docker push / helm install / kubectl
```

Le trust est établi via :
- `attribute_condition = "assertion.repository_owner == '<owner>'"` — limite aux repos du bon owner
- Binding par repo (`attribute.repository/<owner>/<repo>`) — chaque SA est lié à un seul repo

---

## Variables GitHub Actions requises

### Repo `repo-infrastructure`

| Variable | Valeur |
|----------|--------|
| `GCP_PROJECT_ID` | `pfe-2026-495220` |
| `GCP_REGION` | `europe-west1` |
| `GKE_CLUSTER_NAME` | `gke-staging-pfe` |
| `GAR_REPOSITORY_NAME` | `registry-staging-pfe` |
| `GCS_BUCKET_NAME` | `tfstate-pfe-2026` |
| `NODE_COUNT` | `1` |
| `NODE_VM_SIZE` | `e2-standard-2` |
| `GITOPS_REPO` | `mariemmehri/repo-config` |

| Secret | Description |
|--------|-------------|
| `WORKLOAD_IDENTITY_PROVIDER` | Nom complet du WIF provider |
| `SERVICE_ACCOUNT_EMAIL` | Email de `sa-terraform-ci` |

---

## Linting et validation locale

```bash
# Format
terraform fmt -recursive

# Validation syntaxique
for d in backend-config environments/staging \
          modules/gke modules/networking \
          modules/artifact_registry modules/iam; do
  echo "── $d"
  (cd "$d" && terraform init -backend=false && terraform validate)
done

# tflint
tflint --recursive --config=.tflint.hcl

# Checkov (sécurité)
checkov -d . --framework terraform --config-file .checkov.yaml
```

---

## Commandes utiles après apply

```bash
# Se connecter au cluster
gcloud container clusters get-credentials gke-staging-pfe \
  --region europe-west1-b --project pfe-2026-495220

# Port-forward ArgoCD
kubectl port-forward svc/argocd-server -n argocd 9089:80
# Interface : http://localhost:9089

# Mot de passe admin ArgoCD
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d

# Vérifier les applications ArgoCD
kubectl get applications -n argocd
```
