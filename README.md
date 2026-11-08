# S2 — Signature keyless Sigstore et provenance SLSA

Une image n'est déployée que si l'on peut prouver **qui** l'a construite et **comment**, sans qu'aucune
clé de signature ne soit stockée nulle part.

```
GitHub Actions (main)                         Lab (Gitea + Zot + VM4)
 build ─► ghcr.io/<groupe>/s2-keyless-slsa     promote-verified-image (workflow_dispatch)
   │        ▲                                    1. cosign verify       identité = ce dépôt / workflow / main
   │ cosign sign (keyless, OIDC GitHub)          2. slsa-verifier       provenance signée par le générateur SLSA
   │        │                                    3. conftest            politique Rego de l'organisation
   └► générateur SLSA v2.1.0 (job isolé)         4. crane copy          même digest dans Zot
      attache la provenance signée               5. deploy-staging      VM4, par digest
            │
   Fulcio (certificat ~10 min) + Rekor (journal public)
```

Par rapport au TP (`sign-and-verify` avec `cosign.key`), il n'y a plus de clé privée stockée en secret
Gitea, donc plus rien à exfiltrer. L'identité est le jeton OIDC du workflow, et chaque signature est
inscrite dans le journal public Rekor.

## Arborescence

| Chemin | Rôle |
| --- | --- |
| `.github/workflows/release.yml` | build, push ghcr.io, signature keyless, provenance SLSA (générateur v2.1.0) |
| `verify/verify.sh` | vérification complète d'une image, utilisable partout (code 0 = admise, 1 = refusée) |
| `verify/config.env` | identité attendue : dépôt, workflow, branche, générateur |
| `verify/policy/provenance.rego` | politique d'admission ; `provenance_test.rego` = 9 tests |
| `verify/install-tools.sh` | installe cosign, slsa-verifier, conftest, crane (versions et SHA-256 figés) |
| `lab/promote.yml` | workflow Gitea : vérifier, promouvoir dans Zot, déployer sur VM4 |
| `demo/attaque.md` | scénarios refusés pour la démonstration |
| `app/`, `Dockerfile` | application de démonstration (API Flask) |

## Rejouer la démonstration

### Prérequis

- Linux x86_64 avec `curl`, `jq`, `bash` ; Docker seulement pour le scénario « image non signée ».
- Un compte GitHub pour le dépôt du groupe et, pour la démo d'attaque, un second compte.
- Accès réseau à `github.com`, `ghcr.io` et `*.sigstore.dev`, avec une horloge synchronisée.

### 1. Construire et signer (GitHub)

1. Créer le dépôt `<groupe>/s2-keyless-slsa` sur GitHub et y pousser ce contenu.
2. Pousser sur `main` : le workflow `release` lance `build`, puis `provenance`.
3. Rendre le paquet public : GitHub → Packages → `s2-keyless-slsa` → Package settings → Change visibility.
   Sinon, fournir un jeton (voir l'étape 2).
4. Noter le digest affiché à l'étape « Build et publication », ou :
   `crane digest ghcr.io/<groupe>/s2-keyless-slsa:<sha du commit>`.

### 2. Vérifier (n'importe quelle machine)

```bash
./verify/install-tools.sh ./bin && export PATH="$PWD/bin:$PATH"
sed -i 's|CHANGEME|<groupe>|' verify/config.env
export GH_TOKEN=<PAT avec read:packages>   # slsa-verifier le demande pour ghcr.io
./verify/verify.sh ghcr.io/<groupe>/s2-keyless-slsa@sha256:<digest>
```

Sortie attendue : `[1/3]`, `[2/3]` et `[3/3]` à OK, puis `ADMISE`. Les preuves restent dans `out/`
(`signature.json`, `provenance.json`, `policy-input.json`).

Tests de la politique : `conftest verify --policy verify/policy` (9 tests).

### 3. Promouvoir et déployer (lab Gitea)

1. Copier `verify/` dans le dépôt Gitea, puis `lab/promote.yml` dans `.gitea/workflows/promote.yml`.
2. Secrets Gitea du dépôt : `GHCR_TOKEN` (PAT GitHub, scope `read:packages` seul), `ZOT_USERNAME`,
   `ZOT_PASSWORD`, `SSH_DEPLOY_KEY`, `ADMIN_TOKEN`. Plus de `COSIGN_KEY` ni de `COSIGN_PASSWORD`.
3. Gitea → Actions → `promote-verified-image` → Exécuter, avec en entrée l'image par digest.
4. Contrôle : `curl http://10.0.0.14:8080/health`.

### 4. Scénarios d'attaque

Voir `demo/attaque.md` : image d'un autre dépôt signée et prouvée (refusée), image non signée
(refusée), référence par tag (refusée).

## Versions figées

| Outil | Version | Contrôle |
| --- | --- | --- |
| cosign | v3.1.4 | SHA-256 dans `install-tools.sh` |
| slsa-verifier | v2.7.0 | SHA-256 dans `install-tools.sh` |
| conftest | v0.71.1 | SHA-256 dans `install-tools.sh` |
| crane | v0.22.1 | SHA-256 dans `install-tools.sh` |
| slsa-github-generator | v2.1.0 | tag exigé par le générateur, vérifié via `BUILDER_ID` |
| Actions GitHub | voir `release.yml` | épinglées par SHA de commit |

## Dépannage

| Symptôme | Cause probable | Correction |
| --- | --- | --- |
| `[2/3]` : `denied` ou `UNAUTHORIZED` sur ghcr.io | `GH_TOKEN` absent | PAT `read:packages` dans `GH_TOKEN` |
| `[1/3]` refusée sur l'image légitime | `config.env` non adapté (`CHANGEME`), ou image construite depuis une autre branche | vérifier `SOURCE_REPO`, `BRANCH` et le commit |
| `[2/3]` : aucune attestation | le job `provenance` a échoué ou n'a pas tourné | consulter le run GitHub |
| erreurs TUF ou certificat dans le lab | horloge décalée ou `*.sigstore.dev` filtré | NTP, puis tester `curl -I https://tuf-repo-cdn.sigstore.dev` |
| pas de bouton Exécuter dans Gitea | `workflow_dispatch` non pris en charge par la version de Gitea | mettre à jour Gitea ou déclencher par un push |
