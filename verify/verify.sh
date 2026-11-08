#!/usr/bin/env bash
# Verifie une image avant de l'admettre : signature keyless, provenance SLSA, politique Rego.
# Usage : ./verify/verify.sh ghcr.io/<owner>/<repo>@sha256:<digest>
# Code de retour : 0 = image admise, 1 = image refusee.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=verify/config.env
source "${VERIFY_CONFIG:-$DIR/config.env}"
OUT="${OUT_DIR:-./out}"
mkdir -p "$OUT"

IMAGE="${1:-}"
# Reference immuable obligatoire : on verifie et on deploie le meme digest (pas de TOCTOU).
if ! [[ "$IMAGE" =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}$ ]]; then
  echo "REFUSEE : reference par tag ou invalide, digest obligatoire (ghcr.io/<owner>/<repo>@sha256:<64 hex>)" >&2
  exit 1
fi
DIGEST="${IMAGE##*@sha256:}"
IDENTITY="https://${SOURCE_REPO}/${WORKFLOW_PATH}@refs/heads/${BRANCH}"

for tool in cosign slsa-verifier conftest jq; do
  command -v "$tool" >/dev/null || { echo "Outil manquant : $tool (voir verify/install-tools.sh)" >&2; exit 1; }
done

fail() { echo "REFUSEE : $1" >&2; exit 1; }

echo "Image    : $IMAGE"
echo "Identite : $IDENTITY"
echo

echo "[1/3] Signature keyless (Fulcio + Rekor)"
cosign verify "$IMAGE" \
  --certificate-identity "$IDENTITY" \
  --certificate-oidc-issuer "$OIDC_ISSUER" \
  --certificate-github-workflow-repository "${SOURCE_REPO#github.com/}" \
  --certificate-github-workflow-ref "refs/heads/${BRANCH}" \
  > "$OUT/signature.json" 2> "$OUT/signature.log" \
  || { cat "$OUT/signature.log" >&2; fail "aucune signature valide pour l'identite attendue"; }
echo "      OK : signee par $IDENTITY"

echo "[2/3] Provenance SLSA (generateur isole, signature keyless)"
slsa-verifier verify-image "$IMAGE" \
  --source-uri "$SOURCE_REPO" \
  --source-branch "$BRANCH" \
  --builder-id "$BUILDER_ID" \
  --print-provenance \
  > "$OUT/provenance.json" 2> "$OUT/provenance.log" \
  || { cat "$OUT/provenance.log" >&2; fail "provenance absente ou non conforme"; }
echo "      OK : $(grep -m1 -o 'Verified build using builder.*' "$OUT/provenance.log" || echo 'provenance verifiee')"

echo "[3/3] Politique de l'organisation (Rego)"
jq -n \
  --arg digest "$DIGEST" \
  --arg builder "$BUILDER_ID" \
  --arg repo "$SOURCE_REPO" \
  --arg branch "$BRANCH" \
  --arg workflow "$WORKFLOW_PATH" \
  --arg events "$ALLOWED_EVENTS" \
  --slurpfile statement "$OUT/provenance.json" \
  '{expected: {digest: $digest, builder_id: $builder, source_repo: $repo, branch: $branch,
               workflow_path: $workflow, allowed_events: ($events | split(","))},
    statement: $statement[0]}' > "$OUT/policy-input.json"
conftest test "$OUT/policy-input.json" --policy "$DIR/policy" --no-color \
  || fail "la provenance viole la politique"

echo
echo "ADMISE : $IMAGE"
