# Module ACR

Crée l'Azure Container Registry.

## Inputs

| Variable            | Description            |
| ------------------- | ---------------------- |
| acr_name            | Nom unique du registry |
| resource_group_name | Nom du RG              |
| location            | Région Azure           |
| environment         | Nom de l'env           |

## Outputs

| Output           | Description     |
| ---------------- | --------------- |
| acr_id           | ID du registry  |
| acr_login_server | URL du registry |
