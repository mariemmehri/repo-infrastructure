# GitOps DevOps Platform — HR Portal (SIRH) on GKE

Plateforme DevOps/GitOps complète pour le déploiement automatisé d'une application HR Portal (SIRH) conteneurisée sur Google Kubernetes Engine (GKE).  
Projet de Fin d'Études — Cycle Ingénieur — Sopra HR Software.

---

## Vue d'ensemble

Ce projet implémente une chaîne de déploiement entièrement automatisée : un `git push` sur la branche `main` déclenche la compilation, les tests, la construction des images Docker, le scan de sécurité, la mise à jour de la configuration GitOps, et enfin le déploiement sur GKE via ArgoCD — sans aucune intervention manuelle.

```
Developer git push
       │
       ▼
GitHub Actions CI (repo-app)
  ├── mvn verify (backend)
  ├── ng build (frontend)
  ├── docker build + trivy scan
  ├── docker push → Google Artifact Registry
  └── yq patch values-staging.yaml → push repo-config
                                           │
                                           ▼
                                    ArgoCD détecte le diff
                                           │
                                           ▼
                                    helm upgrade → GKE staging
```

---

## Architecture — 3 couches

| Couche | Dépôt | Technologie | Responsabilité |
|--------|-------|-------------|----------------|
| 0 — Application | `repo-app/` | Spring Boot + Angular | Code source, CI/CD |
| 1 — Infrastructure | `repo-infrastructure/environments/` | Terraform | VPC, GKE, Artifact Registry, IAM |
| 2 — Bootstrap | `workflow-infra.yml` job `bootstrap-argocd` | Helm + kubectl | Installation ArgoCD (idempotent) |
| 3 — GitOps | `repo-config/` | ArgoCD + Helm | Déploiement continu des applications |

La séparation stricte des couches garantit qu'un changement applicatif ne déclenche jamais un plan Terraform, et qu'ArgoCD n'a jamais accès aux ressources cloud.

---

## Structure des dépôts

```
stage pfe/
├── repo-app/                        # Application fullstack
│   ├── backend/                     # Spring Boot 3.2 / Java 17
│   ├── frontend/                    # Angular 17 / Nginx
│   ├── docker-compose.yml           # Dev local
│   └── .github/workflows/ci.yml    # CI/CD principal
│
├── repo-infrastructure/             # Infrastructure as Code
│   ├── backend-config/              # GCS state + WIF (run once)
│   ├── environments/staging/        # GCP infra : VPC, GKE, GAR, IAM
│   ├── modules/                     # Modules réutilisables
│   │   ├── networking/
│   │   ├── gke/
│   │   ├── artifact_registry/
│   │   └── iam/
│   └── .github/workflows/
│       └── workflow-infra.yml       # Pipeline unique : infra + bootstrap ArgoCD
│
└── repo-config/                     # Source de vérité GitOps
    ├── apps/children/staging.yaml   # Application ArgoCD staging
    └── charts/hr-app/               # Helm chart
```

---

## Stack technique

| Domaine | Technologie |
|---------|-------------|
| Cloud | Google Cloud Platform (GCP) |
| Kubernetes | GKE — `europe-west1-b` |
| Registry | Google Artifact Registry |
| IaC | Terraform 1.7.5 + GCS backend |
| CI/CD | GitHub Actions |
| GitOps | ArgoCD (App-of-Apps) |
| Packaging K8s | Helm 3 |
| Authentification | Workload Identity Federation (OIDC) |
| Backend | Spring Boot 3.2, Java 17, Maven |
| Frontend | Angular 17, TypeScript, Nginx |
| Conteneurs | Docker, eclipse-temurin:17-jre-alpine |
| Sécurité images | Trivy (scan CRITICAL) |
| Lint infra | tflint + Checkov |

---

## Flux de déploiement complet

### Démarrage initial (une seule fois)

```bash
# Étape 0 — Créer le state backend et le WIF
cd repo-infrastructure/backend-config
terraform init && terraform apply

# Étape 1 — Provisionner l'infra GCP + bootstrap ArgoCD
# Pousser sur main déclenche workflow-infra.yml automatiquement :
#   validate → lint → plan → apply → bootstrap-argocd
git push origin main
```

### Cycle de développement normal

```bash
# Dans repo-app/
git add . && git commit -m "feat: ..."
git push origin main
# → GitHub Actions s'exécute automatiquement
# → ArgoCD réconcilie le cluster dans les minutes suivantes
```

### Accès ArgoCD UI

```bash
gcloud container clusters get-credentials gke-staging-pfe \
  --region europe-west1-b --project pfe-2026-495220
kubectl port-forward svc/argocd-server -n argocd 9089:80
# UI : http://localhost:9089  |  user : admin
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

### Développement local

```bash
cd repo-app
docker compose up --build
# Backend : http://localhost:8081/api/health
# Frontend : http://localhost:80
```

---

## CI/CD Workflows

### 1. Application CI (`repo-app/.github/workflows/ci.yml`)

**Déclencheur :** push ou PR sur `main`

```
Job 1 : backend-ci      → mvn verify, upload JAR
Job 2 : frontend-ci     → npm run build, upload dist
Job 3 : docker-build-push (push uniquement)
         ├── Download artefacts
         ├── Auth GCP via OIDC (WIF)
         ├── docker build backend + frontend
         ├── Scan Trivy (CRITICAL, exit-code: 1)
         ├── docker push → GAR (tag: SHA court + latest)
         └── yq patch values-staging.yaml → commit → push repo-config
```

### 2. Infrastructure + Bootstrap (`repo-infrastructure/.github/workflows/workflow-infra.yml`)

**Déclencheur :** push sur `environments/**`, `modules/**`, schedule quotidien, `workflow_dispatch`

| Job | Rôle |
|-----|------|
| validate | `terraform fmt -check`, `terraform validate` sur tous les modules |
| lint | `tflint --recursive` |
| plan | `terraform plan -detailed-exitcode`, commentaire PR, upload artifact |
| apply | `terraform apply` si exitcode=2 — protégé par env `staging-apply` |
| bootstrap-argocd | `helm upgrade --install argocd` + `kubectl apply root-app` — idempotent |
| detect-drift | `terraform plan -refresh-only`, ouvre une issue si dérive |
| destroy | Cleanup ArgoCD → `terraform destroy` — protégé par env `staging-destroy` |
| unlock | Force-unlock état GCS bloqué (escape hatch) |

---

## Décision architecturale clé — Bootstrap ArgoCD via GitHub Actions

ArgoCD est installé par le job `bootstrap-argocd` de `workflow-infra.yml` via `helm upgrade --install` et `kubectl apply`. Ce choix maintient un seul Terraform state (`prefix=staging`) dédié à l'infrastructure GCP, sans state ArgoCD séparé. Le job est idempotent — il vérifie si ArgoCD est déjà présent avant d'agir — et relançable à tout moment via `action=bootstrap`.

---

## Sécurité

- **Workload Identity Federation** : GitHub Actions s'authentifie sur GCP via OIDC. Aucune clé JSON service account.
- **Deux SA séparés** : `sa-terraform-ci` (droits infra : container.admin, compute.networkAdmin, iam.serviceAccountAdmin…) et `sa-github-actions` (uniquement `artifactregistry.writer`).
- **Least privilege IAM** : `modules/iam/` accorde à `sa-terraform-ci` le droit `iam.serviceAccountUser` uniquement sur les SA GKE de l'environnement — pas sur l'ensemble du projet.
- **Trivy** : scan de toute image CRITICAL avant push. Le job échoue si une CVE critique non patchée est trouvée.
- **Checkov** : analyse statique de sécurité du code Terraform.
- **Utilisateurs non-root** dans tous les Dockerfiles.
- **Images Alpine** : surface d'attaque minimale.
- **GitHub Environments** : approbation manuelle requise pour `terraform destroy`.

---

## Variables GitHub requises

### Repo `repo-app`

| Variable | Exemple |
|----------|---------|
| `GCP_PROJECT_ID` | `pfe-2026-495220` |
| `GCP_REGION` | `europe-west1` |
| `GAR_REPOSITORY` | `pfe-2026-495220/registry-staging-pfe` |
| `GCP_WORKLOAD_PROVIDER` | `projects/.../providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | `sa-github-actions@....iam.gserviceaccount.com` |
| `CONFIG_REPO` | `mariemmehri/repo-config` |

| Secret | Description |
|--------|-------------|
| `GH_PAT` | Personal Access Token avec droit `contents:write` sur repo-config |

### Repo `repo-infrastructure`

| Variable | Exemple |
|----------|---------|
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
| `WORKLOAD_IDENTITY_PROVIDER` | Provider WIF complet |
| `SERVICE_ACCOUNT_EMAIL` | `sa-terraform-ci@....iam.gserviceaccount.com` |

---

## Documentation par composant

- [repo-app/README.md](repo-app/README.md) — Application fullstack et pipeline CI/CD
- [repo-app/backend/README.md](repo-app/backend/README.md) — API Spring Boot
- [repo-app/frontend/README.md](repo-app/frontend/README.md) — SPA Angular
- [repo-infrastructure/README.md](repo-infrastructure/README.md) — Infrastructure Terraform + bootstrap ArgoCD
- [repo-config/README.md](repo-config/README.md) — Helm chart et manifests ArgoCD

---

## Améliorations recommandées

| Priorité | Amélioration |
|----------|--------------|
| Haute | Activer l'Ingress + cert-manager (TLS) pour exposer l'application |
| Haute | Ajouter `resources` limits/requests dans les templates Helm |
| Haute | Ajouter `livenessProbe` / `readinessProbe` (nécessite Spring Boot Actuator) |
| Haute | Smoke tests post-déploiement dans le CI |
| Moyenne | Observabilité : kube-prometheus-stack (Prometheus + Grafana) |
| Moyenne | Gestion des secrets : External Secrets Operator |
| Moyenne | Environnement production avec promotion manuelle |
| Faible | HorizontalPodAutoscaler sur le backend |
| Faible | Network Policies Kubernetes (deny-all par défaut) |
