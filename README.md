# repo-infrastructure — Infrastructure as Code GCP

Infrastructure complète Google Cloud Platform pour la plateforme GitOps HR Portal (SIRH).
Terraform 1.7.5 — Backend GCS — Workload Identity Federation — ArgoCD bootstrappé via GitHub Actions.

---

## Vue d'ensemble

Ce dépôt gère deux responsabilités distinctes avec des cycles de vie séparés :

| Phase | Répertoire | Responsabilité | State |
|-------|-----------|----------------|-------|
| **Pré-requis** (run once) | `backend-config/` | GCS state bucket + Workload Identity Federation | local |
| **Infra** | `environments/staging/` | VPC, GKE, Artifact Registry (staging + prod), IAM, buckets de backup CNPG | GCS `prefix=staging` |

Il n'existe **qu'un seul root Terraform actif** (`environments/staging`) — pas de `environments/dev` ni `environments/prod`. Les trois environnements applicatifs (`dev`/`staging`/`prod`) sont des **namespaces Kubernetes** sur le même cluster GKE provisionné ici, pas des racines Terraform séparées ; leur séparation vit dans `repo-config` (ArgoCD), pas ici.

---

## Structure

```
repo-infrastructure/
├── backend-config/              # Run once — crée le backend et le WIF
│   ├── main.tf                  # GCS bucket (state remote) + bucket de logs d'accès
│   ├── wif.tf                   # Workload Identity Federation + 2 SA
│   ├── variables.tf
│   └── outputs.tf                # Valeurs à copier dans les secrets GitHub
│
├── environments/staging/        # Seul root Terraform actif
│   ├── main.tf                  # Orchestration de 8 blocs de module (5 sources distinctes)
│   ├── providers.tf              # Provider Google + backend GCS (vide, configuré via -backend-config)
│   ├── variables.tf
│   ├── outputs.tf                # kubectl command, argocd_portforward, ingress_ips, cnpg_backup_*...
│   ├── backend.hcl.example
│   └── terraform.tfvars.example
│
├── modules/                     # Modules Terraform réutilisables
│   ├── networking/               # VPC + subnet GKE
│   ├── gke/                      # Cluster GKE + node pool (pure compute)
│   ├── artifact_registry/        # Google Artifact Registry — instancié 2x (staging + prod)
│   ├── iam/                      # Identités et IAM par environnement
│   └── cnpg_backup/               # Bucket GCS + SA dédiée pour les backups CNPG — instancié 3x (staging/dev/prod)
│
├── scripts/
│   ├── test-backup-restore.sh        # Vérification backup/restore CNPG (pg-staging)
│   └── cnpg-restore-single-row.sh    # Suppression + restauration d'une ligne précise depuis le backup GCS (pg-dev)
│
├── .checkov.yaml                 # Gating de sévérité + liste de skips documentés
├── .tflint.hcl
└── .github/workflows/
    └── workflow-infra.yml        # Pipeline unique : infra + bootstrap ArgoCD
```

Il n'y a **pas** de fichier `moved.tf` dans `environments/staging/` — ne pas en chercher un, aucune migration de state de ce type n'est en cours.

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
cp terraform.tfvars.example terraform.tfvars
# variables.tf exige aussi github_owner / github_infra_repo / github_app_repo (sans défaut,
# utilisées pour scoper le binding WIF de chaque SA à son propre repo) — le .tfvars.example
# committé ne contient que project_id/region/bucket_name, ajouter les trois manuellement

terraform init
terraform apply
```

**Ce que cela crée :**
- Bucket GCS de state (nom = `var.bucket_name`) + son bucket de logs d'accès (`<bucket_name>-logs`), tous deux avec versioning (7 versions max) et `public_access_prevention = "enforced"`
- Pool Workload Identity Federation `github-pool-v2`
- Provider WIF `github-provider` (trust tokens OIDC de GitHub Actions), scopé par `attribute_condition = "assertion.repository_owner == '<owner>'"`
- Service Account `sa-terraform-ci` — droits projet : `container.admin`, `compute.networkAdmin`, `artifactregistry.admin`, `storage.admin`, `iam.serviceAccountAdmin`, `resourcemanager.projectIamAdmin`
- Service Account `sa-github-actions` — droits : `artifactregistry.writer`, `container.developer`, `storage.objectViewer`

> Note : `iam.serviceAccountUser` n'est **pas** accordé à `sa-terraform-ci` au niveau projet. Ce droit est accordé précisément par `modules/iam/` sur chaque SA GKE d'environnement — principe du moindre privilège.

**Après l'apply, copier les outputs dans les secrets GitHub :**

```bash
terraform output workload_identity_provider  # → secret WORKLOAD_IDENTITY_PROVIDER (repo-infrastructure)
terraform output terraform_ci_sa_email       # → secret SERVICE_ACCOUNT_EMAIL (repo-infrastructure)
terraform output github_actions_sa_email     # → var GCP_SERVICE_ACCOUNT (repo-app)
```

---

## Infra GCP — `environments/staging/`

Provisionne toutes les ressources cloud fondamentales via **8 blocs de module issus de 5 sources distinctes** — `artifact_registry` est instancié deux fois (registre staging/dev + registre prod isolé), `cnpg_backup` est instancié trois fois (un bucket de backup par environnement applicatif).

```bash
cd environments/staging
cp terraform.tfvars.example terraform.tfvars
# éditer : project_id, cluster_name, registry_name, node_count, max_node_count, node_vm_size,
#          cnpg_backup_bucket_name, cnpg_backup_bucket_name_dev, cnpg_backup_bucket_name_prod
#          (ces trois derniers n'ont AUCUN défaut — terraform plan/apply échoue sans eux)

terraform init \
  -backend-config="bucket=<bucket_name du backend-config>" \
  -backend-config="prefix=staging"

terraform fmt -check -recursive    # CI enforced
terraform validate
terraform plan
```

**Ce que cela crée :**

| Ressource | Détail |
|-----------|--------|
| VPC | `vpc-staging-pfe`, `auto_create_subnetworks = false` |
| Subnet GKE | `subnet-gke-staging`, CIDR `10.0.1.0/24` (défaut), Private Google Access, VPC Flow Logs |
| Artifact Registry (staging) | `registry-staging-pfe`, format DOCKER — cible des builds CI normaux (dev + staging) |
| Artifact Registry (prod) | `registry-prod-pfe` (défaut), format DOCKER — **jamais écrit par la CI normale**, uniquement par `crane copy` dans `promote-prod.yml` |
| Buckets de backup CNPG ×3 | un par environnement (staging/dev/prod), `lifecycle { prevent_destroy = true }`, SA dédiée `sa-cnpg-<env>-backup` avec binding Workload Identity vers le KSA CNPG correspondant |
| IP statiques globales ×3 | `ip-hr-dev` / `ip-hr-staging` / `ip-hr-prod` — réservées pour l'Ingress GCE natif de chaque environnement (voir `repo-config`) |
| Service Account nodes | `sa-gke-staging-pfe` — 5 rôles : `artifactregistry.reader`, `logging.logWriter`, `monitoring.metricWriter`, `monitoring.viewer`, `stackdriver.resourceMetadata.writer` |
| GKE Cluster | zonal (`europe-west1-b`), VPC-native, Workload Identity activé, `deletion_protection = false` |
| Node Pool | node pool nommé `default` (remplace le pool par défaut GKE supprimé), spot VMs, autoscaling `node_count`↔`max_node_count`, disk 30 Go (défaut) |
| IAM Binding | `sa-terraform-ci` → `serviceAccountUser` sur `sa-gke-staging-pfe` et sur le SA Compute Engine par défaut (scope étroit, pas projet-wide) |

### Modules détaillés

#### `modules/networking/`

Crée un VPC personnalisé et un subnet dédié au GKE avec Private Google Access activé et des VPC Flow Logs (`aggregation_interval = INTERVAL_5_SEC`, `flow_sampling = 0.5`).

```hcl
google_compute_network.main       # VPC principal
google_compute_subnetwork.gke     # Subnet 10.0.1.0/24 (défaut)
```

#### `modules/artifact_registry/`

Crée un repository Docker dans Google Artifact Registry. Instancié **deux fois** dans `main.tf` — `module.artifact_registry` (staging, `environment = "staging"`) et `module.artifact_registry_prod` (`acr_name = var.prod_registry_name`, défaut `registry-prod-pfe`, `environment = "prod"`). L'URL complète de l'image :
```
europe-west1-docker.pkg.dev/<project>/<repo>/<image>:<tag>
```

#### `modules/iam/`

Couche d'identité par environnement. Trois responsabilités :

- Crée le Service Account GKE nodes `sa-gke-{env}-pfe`
- Lui accorde les 5 rôles minimum requis (logging, monitoring, artifactregistry, stackdriver)
- Accorde à `sa-terraform-ci` le droit `iam.serviceAccountUser` sur ce SA et sur le SA Compute Engine par défaut

```hcl
# Input  : project_id, environment, terraform_ci_sa_email (chaîne construite à la main dans
#          main.tf, PAS une lecture de state distant depuis backend-config), developer_group_email (nullable)
# Output : gke_nodes_sa_email → consommé par modules/gke
```

`terraform_ci_sa_email` est construit inline dans `main.tf` comme `"sa-terraform-ci@${var.project_id}.iam.gserviceaccount.com"` — si ce nom de compte change un jour dans `backend-config/wif.tf`, rien ici ne détecte automatiquement la dérive (deux states Terraform séparés, aucun `terraform_remote_state`).

La variable `developer_group_email` est optionnelle (`default = null`). Quand elle est renseignée, un groupe Google obtient `container.clusterViewer`.

#### `modules/gke/`

Reçoit `gke_nodes_sa_email` en input depuis `modules/iam/` — ne crée aucune identité. `depends_on = [module.networking, module.iam]`.

- Cluster **zonal** (`${var.region}-b`, soit `europe-west1-b`), pas régional
- Désactive le node pool par défaut (`remove_default_node_pool = true`) — remplacé par un pool nommé `default` (nom du *resource*, pas "le pool par défaut de GKE")
- Mode VPC-native + Workload Identity (`workload_pool = "${project_id}.svc.id.goog"`)
- **NetworkPolicy appliquée via GKE Dataplane V2** (`datapath_provider = "ADVANCED_DATAPATH"`, Cilium/eBPF) — **pas** l'ancien addon Calico (`network_policy{enabled=true}`), qui a été retiré car Calico/iptables ne peut pas enforcer une NetworkPolicy egress contre une ClusterIP de Service. Checkov `CKV_GCP_12` (qui ne reconnaît que l'ancien bloc Calico) est skippé en conséquence — ne pas lire ce skip comme "NetworkPolicy désactivée".
- `binary_authorization.evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"` (CKV_GCP_66)
- `master_auth.client_certificate_config.issue_client_certificate = false` (CKV_GCP_13) — WIF/OIDC uniquement
- `master_authorized_networks_config` = `0.0.0.0/0` — ouvert intentionnellement pour les IP dynamiques des runners GitHub Actions (CKV_GCP_25, skippé, à resserrer post-PFE)
- Shielded Nodes (Secure Boot + Integrity Monitoring) sur le node pool réel
- Spot VMs (`spot = true`) + autoscaling (`min_node_count`/`max_node_count`) — nodes préemptables, coût réduit pour du staging
- `management { auto_upgrade = true, auto_repair = true }`

#### `modules/cnpg_backup/`

Provisionne, par environnement, le bucket GCS de destination des backups CloudNativePG (barman-cloud) et l'identité qui y écrit :
- Un `google_storage_bucket` (`force_destroy = false`, **`lifecycle { prevent_destroy = true }`**) — voir la note destroy plus bas.
- Un GSA dédié `sa-cnpg-<env>-backup` (séparé du SA des nodes GKE — un SA par usage), avec `roles/storage.objectAdmin` (écriture) et `roles/storage.legacyBucketReader` (le préflight de barman-cloud a besoin de `storage.buckets.get`, absent de `objectAdmin` seul).
- Un binding Workload Identity permettant au KSA du Cluster CNPG (`<ksa_namespace>/<ksa_name>`) d'impersonner ce GSA sans clé téléchargée.

Instancié trois fois : `module.cnpg_backup` (staging), `module.cnpg_backup_dev`, `module.cnpg_backup_prod`. L'opérateur CNPG / la ressource `Cluster` / le plugin barman-cloud qui consomment réellement ce bucket vivent dans `repo-config`, pas ici.

---

## Bootstrap ArgoCD — job GitHub Actions

ArgoCD est installé par le job `bootstrap-argocd` dans `workflow-infra.yml`.

**Déclenchement :**
- Automatiquement après chaque run (`if: always()`), même si `apply` a été sauté (infra déjà à jour)
- Manuellement via `workflow_dispatch` → action `bootstrap` (force une réinstallation même si ArgoCD est déjà présent)
- Sinon, le check `already_bootstrapped` (`kubectl get namespace argocd` + `kubectl get application root-app`) le rend rapide (~5s) si ArgoCD est déjà installé

**Étapes du job :**

```
1. Check already_bootstrapped
   ├── Si ArgoCD namespace + root-app existent (et action != bootstrap) → skip
   └── Sinon → continuer

2. helm repo add argo ... --force-update
   helm upgrade --install argocd argo/argo-cd
   --version 6.7.3 --namespace argocd --set server.service.type=ClusterIP --wait --timeout 600s

3. kubectl wait crd/applications.argoproj.io --timeout=120s

4. kubectl wait pods -l argocd-server --timeout=300s

5. checkout repo-config, kubectl apply -f repo-config/apps/root-app.yaml
```

---

## Workflow GitHub Actions — `workflow-infra.yml`

**Un seul workflow** gère l'ensemble du cycle de vie : infra Terraform + bootstrap ArgoCD.

**Déclencheurs :**
- Push sur `main` (paths: `environments/**`, `modules/**`, `backend-config/**`, le fichier workflow lui-même, `.checkov.yaml`)
- Pull Request vers `main`
- `workflow_dispatch` — input `action` = `plan` (défaut) | `apply` | `destroy-staging` | `bootstrap`

> **Il n'y a plus de déclencheur `schedule`, plus de job `detect-drift`, plus de job `unlock` fonctionnel.** Le cron quotidien a été supprimé (commit `2bb1607`), `detect-drift` a été supprimé entièrement (`fa8b32c`, pas juste désactivé), et le bloc `unlock` a été entièrement commenté (`5413dea`/`db7d786`) — son YAML existe encore physiquement en bas du fichier mais n'est plus parsé comme un job. Il n'y a donc **aucune exécution périodique non surveillée** de ce workflow, plan-only ou autre. L'auto-libération de lock inline (voir plus bas) reste, elle, active dans `plan`/`apply`.

### Jobs (réels, aujourd'hui)

```
validate (fmt -check -recursive + validate, les 7 dossiers module incl. modules/cnpg_backup)
   ├─> lint (tflint --recursive)         ─┐
   └─> security (checkov, console+SARIF)  ├─> plan ─> apply ─> bootstrap-argocd
                                          ─┘
destroy   (indépendant — workflow_dispatch action=destroy-staging uniquement, env staging-destroy)
```

| Job | Dépendances | Condition | Description |
|-----|-------------|-----------|-------------|
| `validate` | — | Toujours | `terraform fmt -check`, `terraform validate` sur les 7 dossiers module |
| `lint` | validate | Toujours | `tflint --recursive` |
| `security` | validate | Toujours | Checkov, CRITICAL/HIGH bloquants, SARIF → onglet Security GitHub |
| `plan` | lint, security | Sauf destroy, sauf PR forkée | `terraform plan -detailed-exitcode`, commentaire PR, upload artifact |
| `apply` | plan | exitcode=2 + push/dispatch apply | `terraform apply` sur le binaire exact du plan + poll nodes + `kubectl wait` — protégé par env `staging-apply` |
| `bootstrap-argocd` | plan, apply | `always()`, sauf PR, sauf destroy-staging | Helm + kubectl ArgoCD install — idempotent |
| `destroy` | — | dispatch destroy-staging | Cleanup CNPG + ArgoCD → `terraform destroy` — protégé par env `staging-destroy` |

### Détail des jobs clés

**`plan`**
- Écrit `terraform.tfvars` **au runtime** depuis les `vars.*` GitHub (jamais un fichier committé), y compris les trois `cnpg_backup_bucket_name*` (sans défaut Terraform) depuis `vars.CNPG_BACKUP_BUCKET_NAME[_DEV|_PROD]`
- Génère `tfplan.binary` + `tfplan.json`, commente automatiquement les PR avec un tableau Create/Update/Destroy
- Upload l'artifact plan (rétention 1 jour) — `apply` le télécharge plutôt que de re-planifier
- Auto-libère un lock GCS bloqué en cas d'échec (lit `staging/default.tflock`, `terraform force-unlock`)

**`apply`**
- Protégé par GitHub Environment `staging-apply`
- Télécharge l'artifact plan — garantit que ce qui est appliqué est exactement ce qui a été planifié
- Après l'apply, poll (30×10s) jusqu'à ce qu'au moins un node GKE soit enregistré, puis `kubectl wait --for=condition=Ready nodes --all --timeout=300s` (nécessaire à cause des spot VMs + autoscaling, qui peuvent laisser transitoirement zéro node juste après l'apply)

**`bootstrap-argocd`**
- Condition `always()` — tourne même si `apply` a été skippé (infra déjà à jour), sauf sur PR ou `destroy-staging`
- Check `already_bootstrapped` via `kubectl get namespace argocd` — évite une réinstallation sur chaque push
- `action=bootstrap` force la réinstallation même si ArgoCD est présent

**`destroy`**
- Écrit le même `terraform.tfvars` runtime que `plan` (y compris les trois buckets CNPG)
- **Étape ajoutée récemment (`1565367`), doit s'exécuter avant tout le reste** : retire les finalizers de chaque CR `clusters.postgresql.cnpg.io` et les supprime — l'opérateur CNPG doit encore être vivant pour traiter ce finalizer, donc ceci doit précéder la suppression des `Application` ArgoCD (dont `cnpg-operator`)
- Puis : retire les finalizers de toutes les `Application` ArgoCD, les supprime, `helm uninstall argocd`, force-supprime les 3 CRDs ArgoCD + le namespace `argocd`
- Puis `terraform destroy -auto-approve` — protégé par env `staging-destroy`

⚠️ **Ce dernier `terraform destroy` échouera** sur les trois buckets `google_storage_bucket.cnpg_backup` (`lifecycle { prevent_destroy = true }`) — le job ne les retire pas du state ni ne lève ce lifecycle avant l'appel. Pour un destroy complet, gérer ces trois buckets à part (`terraform state rm` + suppression manuelle, ou override temporaire du lifecycle).

⚠️ **Il n'existe plus de job `unlock` dispatchable.** L'auto-libération de lock inline dans `plan`/`apply` reste le seul mécanisme automatique ; en dernier recours, `terraform force-unlock -force <id>` manuellement après lecture de `staging/default.tflock`.

---

## Script utilitaire — `scripts/test-backup-restore.sh`

Vérification santé/restore des backups CNPG pour `pg-staging` (namespace `staging`, cluster `gke-staging-pfe` — non paramétré par environnement au-delà des flags `--project`/`--namespace`).

```bash
./scripts/test-backup-restore.sh                     # lecture seule : santé Cluster, dernier backup, archivage WAL, accessibilité du bucket
./scripts/test-backup-restore.sh --full-restore-test  # opt-in : seed une ligne canari, backup, restore dans un second Cluster jetable, vérifie, nettoie
```
`--full-restore-test` mute l'IAM (binding Workload Identity temporaire) et crée de vraies ressources cluster — nécessite `roles/iam.serviceAccountAdmin` scopé sur `sa-cnpg-staging-backup@<project>.iam.gserviceaccount.com`.

## Script utilitaire — `scripts/cnpg-restore-single-row.sh`

Preuve de restauration d'une donnée précise sur `pg-dev` (namespace `dev`) : supprime une ligne réelle, la restaure depuis le backup GCS (`cnpg-backup-dev-pfe-2026-495220`) dans un cluster CNPG jetable à côté, la réinjecte dans `pg-dev`, vérifie, puis nettoie. Rapport détaillé (RTO/RPO, avant/après) : `docs/backup-restore-drill-report.md`.

```bash
./scripts/cnpg-restore-single-row.sh                                # dry-run : ne touche pas à la vraie ligne, valide juste la chaîne backup->restore
./scripts/cnpg-restore-single-row.sh --live --table employee --where "id = 1"   # drill réel : supprime puis restaure la ligne
```
Comme `test-backup-restore.sh`, `--live` mute l'IAM (binding Workload Identity temporaire) et crée de vraies ressources cluster — même prérequis `roles/iam.serviceAccountAdmin` sur `sa-cnpg-dev-backup@<project>.iam.gserviceaccount.com`. Ne touche jamais à la ressource `Cluster` `pg-dev` elle-même, donc aucun conflit avec le `selfHeal` ArgoCD de l'Application `cnpg-cluster-dev`.

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
terraform apply / helm install / kubectl
```

Le trust est établi via :
- `attribute_condition = "assertion.repository_owner == '<owner>'"` — limite aux repos du bon owner
- Binding par repo (`attribute.repository/<owner>/<repo>`) — chaque SA est lié à un seul repo (`sa-terraform-ci` → `repo-infrastructure` uniquement)

---

## Variables GitHub Actions requises

### Repo `repo-infrastructure`

| Variable | Exemple |
|----------|--------|
| `GCP_PROJECT_ID` | `pfe-2026-495220` |
| `GCP_REGION` | `europe-west1` |
| `GKE_CLUSTER_NAME` | `gke-staging-pfe` |
| `GAR_REPOSITORY_NAME` | `registry-staging-pfe` |
| `GCS_BUCKET_NAME` | nom du bucket créé par `backend-config` |
| `NODE_COUNT` / `MAX_NODE_COUNT` | `1` / `3` (défauts Terraform si omis) |
| `NODE_VM_SIZE` | `e2-standard-2` |
| `CNPG_BACKUP_BUCKET_NAME` / `_DEV` / `_PROD` | un nom de bucket GCS globalement unique chacun — **aucun défaut**, `plan` échoue sans eux |
| `GITOPS_REPO` | `mariemmehri/repo-config` |

| Secret | Description |
|--------|-------------|
| `WORKLOAD_IDENTITY_PROVIDER` | Nom complet du provider WIF |
| `SERVICE_ACCOUNT_EMAIL` | Email de `sa-terraform-ci` |

`prod_registry_name` (défaut `registry-prod-pfe`) n'est alimenté par **aucune** variable GitHub ici — ni `plan`/`apply` ni `destroy` ne l'écrivent dans le `terraform.tfvars` runtime, il garde toujours son défaut. Le nom réellement utilisé côté `repo-app` (`GAR_PROD_REPOSITORY`, s'il existe) est une variable indépendante, consommée uniquement dans `promote-prod.yml`.

---

## Linting et validation locale

```bash
terraform fmt -recursive

for d in backend-config environments/staging modules/gke modules/networking \
         modules/artifact_registry modules/iam modules/cnpg_backup; do
  echo "── $d"
  (cd "$d" && terraform init -backend=false -input=false && terraform validate)
done

tflint --recursive --format compact
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

# Récupérer les IP statiques réservées pour l'Ingress (une par environnement)
terraform output ingress_ips
```

---

## Pour aller plus loin

Voir [CLAUDE.md](CLAUDE.md) pour le détail complet du graphe de dépendances des modules, les variables/défauts exacts, et les internals de `workflow-infra.yml` — cette page reste volontairement plus haut niveau.
