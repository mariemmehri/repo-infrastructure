# Rapport — Test de restauration d'une donnée depuis les sauvegardes CNPG (`pg-dev`)

> Template à remplir après une exécution réelle de `scripts/cnpg-restore-single-row.sh --live`.
> But : prouver qu'une donnée supprimée par erreur dans `pg-dev` est récupérable depuis la sauvegarde GCS (bucket `cnpg-backup-dev-pfe-2026-495220`), sans toucher à la ressource `Cluster` `pg-dev` elle-même (donc sans conflit avec le `selfHeal` ArgoCD de l'Application `cnpg-cluster-dev`).

## Résumé

| Champ | Valeur |
|---|---|
| Date de l'exécution | _à remplir_ |
| Cluster / namespace testés | `pg-dev` / `dev` |
| Table / ligne testée | _à remplir (ex. `employee`, `id = 1`)_ |
| Résultat | PASS / FAIL |
| RTO (suppression → donnée revérifiée dans `pg-dev`) | _à remplir (secondes)_ |
| RPO (déclenchement du backup → suppression) | _à remplir (secondes, ≈ 0 car backup à la demande juste avant)_ |

## Mécanisme testé

1. Backup à la demande (CR `Backup`, plugin `barman-cloud.cloudnative-pg.io`) sur `pg-dev`.
2. Suppression de la ligne choisie sur `pg-dev` (perte de donnée simulée).
3. Restauration du backup dans un cluster CNPG jetable à côté (`pg-dev-restore-test-<run-id>`), via `bootstrap.recovery` + `externalClusters` (CNPG-I barman-cloud), sans toucher au `Cluster` `pg-dev` existant.
4. Extraction de la ligne depuis le cluster de restauration, comparaison avec la baseline.
5. Réinjection de la ligne dans `pg-dev` (via `pg_dump --data-only` de la ligne restaurée, rejoué sur `pg-dev`).
6. Vérification finale + nettoyage du cluster jetable.

## Avant / après

**Baseline (avant suppression) :**
```
_à coller la sortie de l'étape "Baseline row"_
```

**Ligne extraite du cluster de restauration :**
```
_à coller la sortie de l'étape "Restored row"_
```

**Ligne finale dans `pg-dev` (après réinjection) :**
```
_à coller la sortie de l'étape "row is back in pg-dev"_
```

## Preuve applicative

- `GET /api/db-health` (backend `hr-dev`) après restauration : _200 UP / autre_
- Frontend `hr-dev` : la donnée restaurée est-elle réaffichée ? _oui/non_

## Nettoyage

- [ ] Cluster jetable `pg-dev-restore-test-<run-id>` supprimé
- [ ] `ObjectStore` de récupération supprimé
- [ ] `NetworkPolicy` compagnon supprimée
- [ ] Binding Workload Identity temporaire retiré
- [ ] `Backup` CR à la demande supprimé (les objets GCS restent, gérés par la rétention 30j)

## Limites connues

- Volume de données trivial (données de démo `DataSeeder`, 3 employés) — ne prouve pas le comportement à l'échelle.
- `pg-dev` est mono-instance — le test ne couvre pas un failover HA (pertinent uniquement pour `pg-prod`, 3 instances).
- Un seul type d'incident testé (suppression d'une ligne). Non couvert par ce test : perte totale du `Cluster` (sinistre complet), PITR (restauration à un instant précis sans backup à la demande disponible), perte du cluster GKE entier.
- Test exécuté manuellement une fois (vidéo à l'appui) — pas encore intégré à une CI planifiée.

## Pièces jointes

- Vidéo de l'exécution réelle : _lien/chemin_
- Logs bruts complets : _lien/chemin_
