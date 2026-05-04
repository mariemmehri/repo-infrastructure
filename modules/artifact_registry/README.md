# Module Artifact Registry

Crée le Google Artifact Registry (équivalent ACR).

## Inputs

| Variable    | Description            |
| ----------- | ---------------------- |
| acr_name    | Nom unique du registry |
| project_id  | GCP Project ID         |
| region      | Région GCP             |
| environment | Nom de l'env           |

## Outputs

| Output           | Description                        |
| ---------------- | ---------------------------------- |
| acr_id           | ID du repository                   |
| acr_login_server | URL Docker (region-docker.pkg.dev) |
| acr_name         | Nom du repository                  |