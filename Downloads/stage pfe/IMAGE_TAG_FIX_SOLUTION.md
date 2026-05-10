# Solution: ImagePullBackOff - Tag Mismatch Fix

## Problème Identifié

Vos pods obtenaient `ImagePullBackOff` avec le message:

```
failed to resolve reference "europe-west1-docker.pkg.dev/pfe-2026-495220/registry-staging-pfe/todo-backend:352a166": not found
```

### Racine du Problème

Le CI workflow avait une **incohérence de tags**:

| Étape                               | Ancien Comportement                                         | Problème                               |
| ----------------------------------- | ----------------------------------------------------------- | -------------------------------------- |
| **Construction (docker build)**     | Utilise `${{ env.IMAGE_TAG }}` = SHA **complet** (40 chars) | ✓ Correct                              |
| **Push au registre**                | Pousse avec SHA complet                                     | ✓ L'image existe                       |
| **Vérification d'image**            | Cherche avec `${GITHUB_SHA::7}` = SHA **court** (7 chars)   | ✗ Tag n'existe pas                     |
| **Mise à jour values-staging.yaml** | Met le tag court                                            | ✗ Le pod cherche une image inexistante |

**Exemple concret**:

- Image poussée: `todo-backend:d5f8c7e9a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p` (40 chars)
- Tag recherché: `todo-backend:352a166` (7 chars) ❌ **N'existe pas!**

## Solution Appliquée

✅ **Standardisation sur le SHA court (7 caractères) partout**

Changements dans [ci.yml](todo-app/.github/workflows/ci.yml):

1. **Docker Build Backend** (ligne ~112):

   ```diff
   - docker build -t ${{ env.REGISTRY }}/${{ env.BACKEND_IMAGE }}:${{ env.IMAGE_TAG }} ./backend
   + docker build -t ${{ env.REGISTRY }}/${{ env.BACKEND_IMAGE }}:${GITHUB_SHA::7} ./backend
   ```

2. **Scan Backend** (ligne ~120):

   ```diff
   - image-ref: ${{ env.REGISTRY }}/${{ env.BACKEND_IMAGE }}:${{ env.IMAGE_TAG }}
   + image-ref: ${{ env.REGISTRY }}/${{ env.BACKEND_IMAGE }}:${GITHUB_SHA::7}
   ```

3. **Push Backend** (ligne ~127):

   ```diff
   - docker push ${{ env.REGISTRY }}/${{ env.BACKEND_IMAGE }}:${{ env.IMAGE_TAG }}
   + docker push ${{ env.REGISTRY }}/${{ env.BACKEND_IMAGE }}:${GITHUB_SHA::7}
   ```

4. **Même changements appliqués pour Frontend** (lignes ~131-155)

Le script GitOps de mise à jour (`values-staging.yaml`) utilise **déjà** le tag court (`${GITHUB_SHA::7}`), donc il est maintenant aligné! ✓

## Structure Actuelle de `values-staging.yaml`

```yaml
registry:
  host: europe-west1-docker.pkg.dev
  repository: pfe-2026-495220/registry-staging-pfe

backend:
  image:
    name: todo-backend
    tag: "352a166" # ← SHA court (7 chars)

frontend:
  image:
    name: todo-frontend
    tag: "352a166" # ← SHA court (7 chars)
```

Les **templates Helm** construisent l'image complète:

```yaml
image: {{ .Values.registry.host }}/{{ .Values.registry.repository }}/{{ .Values.backend.image.name }}:{{ .Values.backend.image.tag }}
# Résultat: europe-west1-docker.pkg.dev/pfe-2026-495220/registry-staging-pfe/todo-backend:352a166
```

## Flux Corrigé

```
1. Push code → GitHub
   ↓
2. CI/CD démarre
   ├─ Backend: mvn verify ✓
   ├─ Frontend: npm build ✓
   └─ Docker build/push avec tag court (352a166) ✓
      └─ Image existe dans GCP Artifact Registry
   ↓
3. Vérification d'image
   ├─ Cherche: todo-backend:352a166 ✓ TROUVÉE
   ├─ Cherche: todo-frontend:352a166 ✓ TROUVÉE
   ↓
4. GitOps: Update repo-config
   └─ yq met à jour values-staging.yaml avec tag 352a166 ✓
      └─ Commit/push vers todo-config/repo ✓
   ↓
5. ArgoCD détecte le changement
   ├─ Pull config depuis repo-config
   ├─ Helm render les templates
   └─ Deploy pods avec image:352a166 ✓ IMAGE EXISTE
   ↓
6. Kubernetes pull l'image
   └─ ✓ Succès! Pas d'ImagePullBackOff
```

## Tests / Vérification

Pour confirmer que le fix fonctionne:

1. **Pousser un changement** vers `main` du repo `todo-app`
2. **Attendre le CI/CD** (GitHub Actions)
3. **Vérifier les tags créés** dans GCP Artifact Registry:

   ```bash
   gcloud artifacts docker tags list \
     europe-west1-docker.pkg.dev/pfe-2026-495220/registry-staging-pfe/todo-backend
   ```

   → Vous devez voir `352a166` (7 chars), `latest`, etc.

4. **Vérifier la mise à jour** dans `todo-config`:

   ```bash
   cat todo-config/charts/todo-app/values-staging.yaml
   ```

   → Vérifiez que `backend.image.tag` et `frontend.image.tag` correspondent

5. **Vérifier le Pod** dans Kubernetes:
   ```bash
   kubectl describe pod <todo-backend-pod> -n staging
   ```
   → `Image` ne doit pas avoir `<none>` ni erreur de pull

## Résumé des Changements

- ✅ **ci.yml**: Tous les `${{ env.IMAGE_TAG }}` remplacés par `${GITHUB_SHA::7}`
- ✅ **values-staging.yaml**: Déjà à la bonne structure (image.name + image.tag séparés)
- ✅ **Cohérence**: Build → Push → Vérify → Update tous utilisent le **SHA court (7 chars)**

La prochaine exécution du CI/CD devrait résoudre le problème `ImagePullBackOff`! 🚀
