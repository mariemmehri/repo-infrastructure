# Backend Config

Stack dediee a la creation du Storage Account Azure
qui heberge les tfstate des autres stacks.

## Pourquoi cette stack existe

Le Storage Account ne peut pas etre cree par Terraform
avec un remote backend (probleme poulet/oeuf).
Cette stack utilise un state LOCAL intentionnellement.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# Remplir terraform.tfvars avec tes valeurs

terraform init
terraform plan
terraform apply
```

## Outputs importants

Apres apply, note ces valeurs pour les autres stacks :

- storage_account_name -> a mettre dans backend.hcl
- resource_group_name -> a mettre dans backend.hcl
