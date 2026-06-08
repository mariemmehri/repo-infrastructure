# Workflows GitHub — Infrastructure

Ce dossier contient les workflows CI/CD qui gèrent le provisionnement Terraform et le bootstrap GitOps pour l'infrastructure GCP.

Workflows principaux
- `workflow-infra.yml` : provisionnement Terraform de l'infrastructure (réseau, GKE, Artifact Registry, ArgoCD prerequisites). Déclencheurs : `push` sur `main` (paths: `environments/**`, `modules/**`, `backend-config/**`), `pull_request`, `schedule` et `workflow_dispatch` (inputs: `action` ∈ {`plan`,`apply`,`destroy-staging`,`drift`}). Produit des artefacts `tfplan` et commente les PRs.
- `workflow-gitops-bootstrap.yml` : installe ArgoCD et crée l'Application root-app (app‑of‑apps). Déclencheurs : `push` sur `main` (paths: `bootstrap-gitops/**`), `workflow_dispatch` (inputs: `action` ∈ {`plan`,`apply`,`destroy`}), et `workflow_run` déclenché après `Terraform Infra`.

Principaux comportements
- Les runs `plan` produisent des artefacts `tfplan` (upload) et renvoient un `exitcode` (0 = no change, 2 = changes).
- Les runs `apply` téléchargent l'artefact plan et appliquent `terraform apply` (sécurisé pour les runs manuels via `workflow_dispatch`).
- Le workflow bootstrap applique d'abord uniquement ArgoCD puis attend que les CRDs soient prêtes avant d'appliquer la `root-app` (évite l'erreur "CRD Application not found").
- Les workflows utilisent la Workload Identity pour s'authentifier sur GCP via `google-github-actions/auth`.

Secrets et variables requis
- Secrets (Repository → Settings → Secrets):
  - `WORKLOAD_IDENTITY_PROVIDER` (WIF provider full resource name)
  - `SERVICE_ACCOUNT_EMAIL` (service account used by Terraform)

- Repository/Organization variables (Settings → Variables) ou `vars` utilisés par les workflows :
  - `GCP_PROJECT_ID`, `GCP_REGION`, `GKE_CLUSTER_NAME`, `GCS_BUCKET_NAME`, `GITOPS_REPO_URL`, `GITOPS_PATH`, `GAR_REPOSITORY_NAME`, `NODE_COUNT`, `NODE_VM_SIZE`

Environnements GitHub
- `staging-destroy` et `gitops-destroy` protègent les actions de destruction (utilisation manuelle requise via l'UI).

Exécution manuelle (exemples)
Via l'interface GitHub Actions : sélectionnez le workflow puis `Run workflow`, choisissez l'`action` souhaitée.

Via `gh` CLI :
```bash
gh workflow run workflow-infra.yml --ref main -f action=plan
gh workflow run workflow-infra.yml --ref main -f action=apply
gh workflow run workflow-gitops-bootstrap.yml --ref main -f action=plan
gh workflow run workflow-gitops-bootstrap.yml --ref main -f action=apply
```

Bonnes pratiques
- Lancer d'abord `workflow-infra.yml` (Plan → Apply) pour provisionner le cluster et le registre avant de lancer le bootstrap GitOps.
- Conserver secrets/variables à jour et limités en scope.
- Examiner les artefacts `tfplan` avant d'exécuter `apply` sur des environnements partagés.

Fichiers utiles
- [workflow-infra.yml](.github/workflows/workflow-infra.yml) — infra Terraform
- [workflow-gitops-bootstrap.yml](.github/workflows/workflow-gitops-bootstrap.yml) — installation ArgoCD / root-app
