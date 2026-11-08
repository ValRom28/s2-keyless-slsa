#!/usr/bin/env bash
# Recalcule les references de demonstration a partir de l'etat reel de GitHub et de ghcr.io,
# puis ecrit demo/env.sh. A relancer apres chaque push sur main (chaque push = nouvelle image).
# Usage : ./demo/refresh-digests.sh
set -euo pipefail

LEGIT_REPO="${LEGIT_REPO:-ValRom28/s2-keyless-slsa}"
FORK_REPO="${FORK_REPO:-vromanet-test/s2-keyless-slsa}"
UNSIGNED_TAG="${UNSIGNED_TAG:-pirate}"

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/env.sh"

for tool in crane git; do
  command -v "$tool" >/dev/null || { echo "Outil manquant : $tool (voir verify/install-tools.sh)" >&2; exit 1; }
done

# Image construite par le dernier commit de main d'un depot GitHub.
# Affiche "<sha> <image@digest>" et verifie que signature et provenance sont attachees.
image_of_main() {
  local repo="$1" sha img digest tags
  sha="$(git ls-remote "https://github.com/${repo}.git" refs/heads/main | cut -f1)"
  [ -n "$sha" ] || { echo "Impossible de lire main de ${repo}" >&2; return 1; }
  img="ghcr.io/${repo,,}"
  digest="$(crane digest "${img}:${sha}")" || {
    echo "Pas d'image ${img}:${sha} : le run GitHub de ce commit est-il termine et vert ?" >&2; return 1; }
  tags="$(crane ls "$img")"
  grep -qx "sha256-${digest#sha256:}" <<<"$tags" || echo "ATTENTION : pas de signature pour ${img}@${digest}" >&2
  grep -qx "sha256-${digest#sha256:}.att" <<<"$tags" || echo "ATTENTION : pas de provenance pour ${img}@${digest}" >&2
  echo "$sha ${img}@${digest}"
}

read -r LEGIT_SHA LEGIT <<<"$(image_of_main "$LEGIT_REPO")"
read -r FORK_SHA FORK <<<"$(image_of_main "$FORK_REPO")"

LEGIT_IMG="${LEGIT%@*}"
UNSIGNED_DIGEST="$(crane digest "${LEGIT_IMG}:${UNSIGNED_TAG}")" || {
  echo "Pas d'image ${LEGIT_IMG}:${UNSIGNED_TAG} (scenario 2 a preparer)" >&2; exit 1; }
if crane ls "$LEGIT_IMG" | grep -qx "sha256-${UNSIGNED_DIGEST#sha256:}"; then
  echo "ATTENTION : l'image ${UNSIGNED_TAG} porte une signature, le scenario 2 ne marchera pas" >&2
fi
UNSIGNED="${LEGIT_IMG}@${UNSIGNED_DIGEST}"
TAGREF="${LEGIT_IMG}:${LEGIT_SHA}"

cat > "$OUT" <<EOF
# Genere par demo/refresh-digests.sh le $(date '+%Y-%m-%d %H:%M') : ne pas modifier a la main.
# Usage : source demo/env.sh
export LEGIT="${LEGIT}"
export FORK="${FORK}"
export UNSIGNED="${UNSIGNED}"
export TAGREF="${TAGREF}"
# Commits correspondants : legitime ${LEGIT_SHA:0:7}, fork ${FORK_SHA:0:7}
EOF

echo "Ecrit : $OUT"
cat "$OUT"
