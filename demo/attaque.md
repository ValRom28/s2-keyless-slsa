# Scénarios d'attaque pour la démonstration

Chaque scénario doit être **refusé** par `verify/verify.sh` (code de retour 1).
Préparez les images la veille et notez leurs digests ci-dessous.

| Variable | Image | Digest |
| --- | --- | --- |
| `LEGIT` | `ghcr.io/<groupe>/s2-keyless-slsa` (run vert de `main`) | `sha256:…` |
| `FORK` | `ghcr.io/<attaquant>/s2-keyless-slsa` (scénario 1) | `sha256:…` |
| `UNSIGNED` | `ghcr.io/<attaquant>/s2-unsigned` (scénario 2) | `sha256:…` |

## 0. Référence : l'image légitime est admise

```bash
./verify/verify.sh "$LEGIT"        # -> ADMISE
```

## 1. Même outillage, mauvaise identité (scénario principal)

Un membre du groupe joue l'attaquant avec son compte GitHub personnel :

1. Il crée `<attaquant>/s2-keyless-slsa` à partir du dépôt du groupe (fork ou copie).
2. Il modifie l'application, par exemple en ajoutant une route qui renvoie les variables d'environnement.
3. Il pousse sur `main` : le **même** workflow construit, signe en keyless et produit une provenance SLSA valide.

```bash
./verify/verify.sh "$FORK"         # -> REFUSEE : aucune signature valide pour l'identite attendue
```

À montrer : l'image est bien signée et sa provenance est authentique, mais le certificat Fulcio porte
`https://github.com/<attaquant>/…` au lieu de l'identité attendue. Une signature valide ne suffit pas,
il faut épingler **qui** a signé.

Contre-exemple (diapositive « Limites ») : avec une identité trop large, l'image de l'attaquant passe.

```bash
cosign verify "$FORK" \
  --certificate-identity-regexp '.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com   # -> passe !
```

## 2. Image non signée

```bash
docker build -t "ghcr.io/<attaquant>/s2-unsigned:demo" . && docker push "ghcr.io/<attaquant>/s2-unsigned:demo"
UNSIGNED="ghcr.io/<attaquant>/s2-unsigned@$(crane digest ghcr.io/<attaquant>/s2-unsigned:demo)"
./verify/verify.sh "$UNSIGNED"     # -> REFUSEE : no signatures found
```

## 3. Référence par tag au lieu d'un digest

```bash
./verify/verify.sh "ghcr.io/<groupe>/s2-keyless-slsa:latest"   # -> refus immédiat
```

Un tag est mutable : vérifier `:latest` puis déployer `:latest` laisse une fenêtre pour substituer l'image
entre les deux (TOCTOU). On vérifie, copie et déploie toujours le même digest.

## 4. Dans le lab

Lancer le workflow Gitea `promote-verified-image` avec `$FORK` comme entrée : le job
`verify-and-promote` échoue, rien n'est copié dans Zot et `deploy-staging` ne démarre pas.
