# repo-infrastructure — Infrastructure as Code GCP

Infrastructure complète Google Cloud Platform pour l'environnement staging de la plateforme Todo GitOps.  
Terraform 1.7.5 — Backend GCS — Workload Identity Federation.

---

## Vue d'ensemble

Ce dépôt gère deux responsabilités distinctes, chacune avec son propre state Terraform :

| Phase | Répertoire | Responsabilité |
|-------|-----------|----------------|
| **Pré-requis** (run once) | `backend-config/` | GCS state bucket + Workload Identity Federation |
| **Phase A** | `environments/staging/` | VPC, GKE cluster, Artifact Registry |
| **Phase B** | `bootstrap-gitops/` | Installation ArgoCD + root-app ArgoCD |

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
├── environments/staging/        # Phase A — infra GCP
│   ├── main.tf                  # Orchestration des 3 modules
│   ├── providers.tf             # Provider Google + backend GCS
│   ├── variables.tf
│   └── outputs.tf               # kubectl command, argocd_portforward...
│
├── modules/                     # Modules Terraform réutilisables
│   ├── networking/              # VPC + subnet GKE
│   ├── gke/                     # Cluster GKE + node pool + SA
│   └── artifact_registry/       # Google Artifact Registry
│
├── bootstrap-gitops/            # Phase B — ArgoCD bootstrap
│   ├── main.tf                  # Namespace + Helm ArgoCD + root-app manifest
│   ├── providers.tf             # Providers Helm + Kubernetes (lit GKE existant)
│   ├── variables.tf
│   └── outputs.tf
│
├── .github/workflows/
│   ├── workflow-infra.yml           # CI/CD Phase A
│   └── workflow-gitops-bootstrap.yml # CI/CD Phase B
│
└── .tflint.hcl                  # Configuration linter Terraform
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

# Créer terraform.tfvars
cat > terraform.tfvars <<EOF
project_id       = "pfe-2026-495220"
region           = "europe-west1"
bucket_name      = "tfstate-pfe-2026"
github_owner     = "mariemmehri"
github_infra_repo = "repo-infrastructure"
github_app_repo  = "todo-app"
EOF

terraform init
terraform apply
```

**Ce que cela crée :**
- Bucket GCS `tfstate-pfe-2026` avec versioning (7 versions max)
- Pool Workload Identity Federation `github-pool-v2`
- Provider WIF `github-provider` (trust tokens OIDC de GitHub Actions)
- Service Account `sa-terraform-ci` — droits : container.admin, compute.networkAdmin, artifactregistry.admin, iam.serviceAccountAdmin...
- Service Account `sa-github-actions` — droits : artifactregistry.writer uniquement

**Après l'apply, copier les outputs dans les secrets GitHub :**

```bash
terraform output workload_identity_provider  # → GCP_WORKLOAD_PROVIDER (infra + app)
terraform output terraform_ci_sa_email       # → SERVICE_ACCOUNT_EMAIL (infra)
terraform output github_actions_sa_email     # → GCP_SERVICE_ACCOUNT (app)
```

---

## Phase A — Infrastructure GCP (`environments/staging/`)

Provisionne les ressources cloud fondamentales.

```bash
cd environments/staging

cat > terraform.tfvars <<EOF
project_id    = "pfe-2026-495220"
region        = "europe-west1"
cluster_name  = "gke-staging-pfe"
registry_name = "registry-staging-pfe"
node_count    = 1
node_vm_size  = "e2-standard-2"
EOF

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
| Service Account nodes | `sa-gke-staging-pfe`, rôle `artifactregistry.reader` |
| GKE Cluster | VPC-native, Workload Identity activé, deletion_protection=false |
| Node Pool | 1 nœud `e2-standard-2`, spot=true, autoscaling 1-1, disk 30 Go |
| IAM Binding | `sa-terraform-ci` peut utiliser le SA GKE nodes |

### Modules détaillés

#### `modules/networking/`

Crée un VPC personnalisé (pas d'auto-create-subnetworks) et un subnet dédié au GKE avec Private Google Access activé.

```hcl
google_compute_network.main          # VPC principal
google_compute_subnetwork.gke        # Subnet 10.0.1.0/24
```

#### `modules/artifact_registry/`

Crée un repository Docker dans Google Artifact Registry. L'URL complète de l'image sera :
```
europe-west1-docker.pkg.dev/<project>/<repo>/<image>:<tag>
```

#### `modules/gke/`

- Désactive le node pool par défaut (bonne pratique — géré séparément)
- Active le mode VPC-native et Workload Identity
- Crée un node pool avec spot instances (économies de coût en staging)
- Assigne un SA dédié aux nodes avec le minimum de permissions nécessaires

---

## Phase B — Bootstrap GitOps (`bootstrap-gitops/`)

Installe ArgoCD sur le cluster existant et crée le root-app ArgoCD (App-of-Apps).

```bash
cd bootstrap-gitops

cat > terraform.tfvars <<EOF
project_id             = "pfe-2026-495220"
region                 = "europe-west1"
cluster_name           = "gke-staging-pfe"
gitops_repo_url        = "https://github.com/mariemmehri/repo-config"
gitops_target_revision = "main"
gitops_path            = "apps/children"
EOF

terraform init \
  -backend-config="bucket=tfstate-pfe-2026" \
  -backend-config="prefix=bootstrap"

terraform apply
```

### Problème CRD et solution deux phases

**Problème :** Créer `kubernetes_manifest` (Application ArgoCD) dans le même apply que `helm_release.argocd` provoque :
```
the server could not find the requested resource (argoproj.io/v1alpha1, Application)
```
Le CRD `applications.argoproj.io` n'est pas encore enregistré par l'API server au moment où Terraform tente de créer la ressource.

**Solution dans `main.tf` :**
1. `kubernetes_namespace_v1.argocd` — namespace
2. `helm_release.argocd` (wait=true, timeout=600s) — installe ArgoCD et attend que les pods soient Running
3. `kubernetes_manifest.root_app` (depends_on: helm_release) — Application root-app

**Solution dans le workflow GitHub Actions :**
```bash
# Étape 1 : appliquer uniquement ArgoCD
terraform apply -target=helm_release.argocd -auto-approve

# Étape 2 : attendre le CRD (120s max)
kubectl wait --for=condition=established crd/applications.argoproj.io --timeout=120s

# Étape 3 : attendre le pod ArgoCD server (300s max)
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Étape 4 : appliquer le reste (root-app manifest)
terraform apply -auto-approve
```

### Root-app créé par Terraform

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  source:
    repoURL: <gitops_repo_url>
    path: apps/children          # surveille ce dossier
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## Workflows GitHub Actions

### `workflow-infra.yml` — Phase A

**Déclencheurs :**
- Push sur `main` (paths: `environments/**`, `modules/**`, `backend-config/**`)
- Pull Request vers `main`
- Schedule quotidien (13:30 UTC) — drift detection
- `workflow_dispatch` (plan | apply | destroy-staging | drift)

**Jobs :**

| Job | Condition | Description |
|-----|-----------|-------------|
| `validate` | Toujours | fmt, validate, tflint, checkov |
| `plan` | Sauf destroy | `terraform plan -detailed-exitcode` |
| `apply` | exitcode=2 + push | `terraform apply` + attend readiness GKE |
| `detect-drift` | Schedule ou dispatch | `terraform plan -refresh-only`, ouvre issue si dérive |
| `destroy` | dispatch + confirm | Protégé par GitHub Environment `staging-destroy` |

**Commentaire PR automatique :**
Quand un plan détecte des changements sur une PR, le workflow commente automatiquement avec un tableau Create/Update/Destroy et le détail des ressources.

**Drift detection :**
```bash
terraform plan -refresh-only -detailed-exitcode
# exitcode=2 → crée une GitHub Issue avec label "terraform-drift"
# Ne crée pas de doublon si une issue ouverte existe déjà
```

### `workflow-gitops-bootstrap.yml` — Phase B

**Déclencheurs :**
- Push sur `bootstrap-gitops/**`
- `workflow_run` après succès du workflow infra (chaînage automatique)
- `workflow_dispatch` (plan | apply | destroy)

**Job `check-trigger` :** vérifie que si le déclencheur est `workflow_run`, le workflow infra s'est terminé avec succès (`conclusion=success`). Évite de bootstrapper ArgoCD si l'infra a échoué.

**Job `destroy` :** supprime uniquement l'objet `root-app` ArgoCD. Ne touche pas au cluster GKE ni à ArgoCD lui-même. Protégé par GitHub Environment `gitops-destroy`.

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
GCP IAM (Service Account impersonation)
       │  accès aux APIs GCP selon les rôles du SA
       ▼
terraform apply / docker push / kubectl
```

Le trust entre GitHub et GCP est établi via :
- `attribute_condition = "assertion.repository_owner == '<owner>'"` — limite aux repos du bon owner
- Binding par repo (`attribute.repository/<owner>/<repo>`) — chaque SA est lié à un seul repo

---

## Variables GitHub Actions requises

| Variable | Description |
|----------|-------------|
| `GCP_PROJECT_ID` | ID du projet GCP |
| `GCP_REGION` | `europe-west1` |
| `GKE_CLUSTER_NAME` | Nom du cluster |
| `GAR_REPOSITORY_NAME` | Nom du repo Artifact Registry |
| `GCS_BUCKET_NAME` | Nom du bucket state |
| `NODE_COUNT` | Nombre de nodes (1) |
| `NODE_VM_SIZE` | `e2-standard-2` |
| `GITOPS_REPO_URL` | URL HTTPS du repo-config |
| `GITOPS_PATH` | `apps/children` |

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
for d in backend-config environments/staging modules/gke modules/networking modules/artifact_registry; do
  echo "── $d"
  (cd "$d" && terraform init -backend=false && terraform validate)
done

# tflint
tflint --recursive --config=.tflint.hcl

# Checkov (sécurité)
checkov -d . --framework terraform --skip-check CKV_GCP_25,CKV_GCP_71
```

---

## Outputs utiles (après Phase A)

```bash
# Se connecter au cluster
gcloud container clusters get-credentials gke-staging-pfe --region europe-west1-b --project pfe-2026-495220

# Port-forward ArgoCD (après Phase B)
kubectl port-forward svc/argocd-server -n argocd 9089:80
# Interface : http://localhost:9089

# Mot de passe admin ArgoCD
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```
