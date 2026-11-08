# Scénarios d'attaque pour la démonstration

L'image légitime doit être **admise** (code 0). Chaque attaque doit être **refusée** par `verify/verify.sh`
(code 1). Les images sont préparées à l'avance ; on ne fait tourner en direct que la vérification.

## Images de démonstration

| Variable | Image | Digest (au 08/11/2026, à rafraîchir après tout push) |
| --- | --- | --- |
| `LEGIT` | `ghcr.io/valrom28/s2-keyless-slsa` (dernier run vert de `main`) | `sha256:423c22f1508b6eca577a2d7ffd0f82dd689c8d51dc9922b6ef66fbf15d9f1461` |
| `FORK` | `ghcr.io/vromanet-test/s2-keyless-slsa` (fork, même workflow) | `sha256:380ef5a8847d1aa1d53a0bd11c22436f4c0ac21e2af18e63ebf9911754d8749f` |
| `UNSIGNED` | `ghcr.io/valrom28/s2-keyless-slsa:pirate` (poussée hors pipeline) | `sha256:24376bec5eb14ffa28b22d974edc35c8dd4d6911d7530d94467fb73531238774` |
| `TAGREF` | `ghcr.io/valrom28/s2-keyless-slsa:<sha du commit légitime>` | aucun (référence par tag) |

Un digest s'écrit `sha256:<64 hex>`. La forme `sha256-<64 hex>` est le **tag** sous lequel cosign
range la signature de cette image dans le registre, pas une référence d'image.

## Préparer les variables

Chaque push sur `main` produit une nouvelle image légitime : ne pas recopier les digests à la main,
les recalculer depuis GitHub et ghcr.io.

```bash
./verify/install-tools.sh ./bin && export PATH="$PWD/bin:$PATH"
export GH_TOKEN=<PAT classic, scope read:packages>
./demo/refresh-digests.sh      # écrit demo/env.sh et contrôle signatures et provenances
source demo/env.sh
```

`refresh-digests.sh` lit le dernier commit de `main` des deux dépôts GitHub, récupère le digest de l'image
correspondante et vérifie que la signature (`sha256-…`) et la provenance (`sha256-….att`) sont attachées.
Il contrôle aussi que l'image `pirate` n'est pas signée. Les dépôts se changent par variables :
`LEGIT_REPO`, `FORK_REPO`, `UNSIGNED_TAG`.

## Dérouler la démonstration

```bash
./demo/run.sh                  # pause entre chaque scénario ; DEMO_NOPAUSE=1 pour enchaîner
```

Le script affiche chaque commande, son résultat, puis un bilan (`OK` si le code de retour est celui attendu).
Les preuves de chaque scénario restent dans `out/<scénario>/`.

## 0. Référence : l'image légitime est admise

```bash
./verify/verify.sh "$LEGIT"        # -> ADMISE
```

À montrer dans `out/legit/provenance.json` : dépôt, commit et workflow de construction.

```bash
jq '.predicate.invocation.configSource, .predicate.builder.id' out/legit/provenance.json
```

## 1. Même outillage, mauvaise identité (scénario principal)

Le compte `vromanet-test` joue l'attaquant :

1. Il forke `ValRom28/s2-keyless-slsa` et active les workflows du fork.
2. Il ajoute une route `/debug` qui renvoie les variables d'environnement (fuite de `ADMIN_TOKEN`).
3. Il pousse sur `main` : le **même** workflow construit, signe en keyless et produit une provenance SLSA valide.

```bash
./verify/verify.sh "$FORK"         # -> REFUSEE à [1/3] : aucune signature valide pour l'identite attendue
```

À montrer : l'image est bien signée et sa provenance est authentique, mais le certificat Fulcio porte
`https://github.com/vromanet-test/…` au lieu de `https://github.com/ValRom28/…`. Une signature valide
ne suffit pas, il faut épingler **qui** a signé.

### Contre-exemple (diapositive « Limites »)

Avec une identité trop large, l'image de l'attaquant passe :

```bash
cosign verify "$FORK" \
  --certificate-identity-regexp '.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com   # -> passe !
```

## 2. Image non signée

Quelqu'un qui a un accès en écriture au registre pousse une image dans **notre** paquet, sans passer
par le workflow (préparé une fois, avec un PAT `write:packages` révoqué ensuite) :

```bash
docker build -t ghcr.io/valrom28/s2-keyless-slsa:pirate . && docker push ghcr.io/valrom28/s2-keyless-slsa:pirate
```

```bash
./verify/verify.sh "$UNSIGNED"     # -> REFUSEE à [1/3] : no signatures found
```

Le nom de l'image est le bon, mais aucun workflow ne l'a signée. Ne pas repousser `:pirate` :
son digest changerait.

## 3. Référence par tag au lieu d'un digest

```bash
./verify/verify.sh "$TAGREF"       # -> refus immédiat, avant tout appel à cosign
```

Même l'image légitime est refusée par tag. Un tag est mutable (le scénario 2 vient de le montrer avec
`:pirate`) : vérifier un tag puis déployer ce tag laisse une fenêtre pour substituer l'image entre
les deux (TOCTOU). On vérifie, copie et déploie toujours le même digest.

## 4. Dans le lab (Gitea)

Workflow `promote-verified-image` du dépôt `devsecops-lab/s2-promote`, lancé avec *Exécuter le workflow* :

| Entrée | Résultat attendu |
| --- | --- |
| valeur de `$LEGIT` | `verify-and-promote` vert (ADMISE, copie dans Zot), `deploy-staging` vert, `curl http://10.0.0.14:8080/health` répond |
| valeur de `$FORK` | `verify-and-promote` rouge à *Vérification*, rien copié dans Zot, `deploy-staging` ignoré |

Les deux runs sont lancés avant la soutenance et montrés depuis l'historique Gitea.
