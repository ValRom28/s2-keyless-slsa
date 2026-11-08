#!/usr/bin/env bash
# Deroule les scenarios de la demonstration, avec une pause entre chacun.
# Prerequis : PATH contenant bin/ (install-tools.sh), GH_TOKEN (read:packages), demo/env.sh a jour.
# Usage : ./demo/run.sh            (DEMO_NOPAUSE=1 pour enchainer sans pause)
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$DIR")"
[ -f "$DIR/env.sh" ] || { echo "demo/env.sh absent : lancer d'abord ./demo/refresh-digests.sh" >&2; exit 1; }
# shellcheck source=/dev/null
source "$DIR/env.sh"

if [ -t 1 ]; then G=$'\e[1;32m'; R=$'\e[1;31m'; B=$'\e[1m'; N=$'\e[0m'; else G=; R=; B=; N=; fi
RESULTS=()

pause() { [ "${DEMO_NOPAUSE:-0}" = 1 ] || read -rp $'\n[Entree pour continuer] ' _; }

# scenario <titre> <code attendu> <commande...>
scenario() {
  local title="$1" want="$2"; shift 2
  echo; echo "${B}=== ${title} ===${N}"
  echo "\$ $*"; echo
  "$@"; local got=$?
  if [ "$got" -eq "$want" ]; then
    RESULTS+=("${G}OK${N}    ${title}")
  else
    RESULTS+=("${R}ECART${N} ${title} (code ${got}, attendu ${want})")
  fi
  pause
}

counter_example() {
  local subject
  if subject="$(cosign verify "$FORK" \
      --certificate-identity-regexp '.*' \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      --output json 2>/dev/null | jq -r '.[0].optional.Subject // "identite inconnue"')"; then
    echo "${R}PASSE${N} avec une identite non epinglee : signee par ${subject}"
    return 0
  fi
  echo "Refusee (inattendu pour ce contre-exemple)"; return 1
}

cd "$ROOT" || exit 1
scenario "0. Image legitime"                       0 env OUT_DIR=out/legit    ./verify/verify.sh "$LEGIT"
scenario "1. Fork, meme workflow, autre identite"  1 env OUT_DIR=out/fork     ./verify/verify.sh "$FORK"
scenario "1bis. Contre-exemple : identite '.*'"    0 counter_example
scenario "2. Image non signee (tag pirate)"        1 env OUT_DIR=out/unsigned ./verify/verify.sh "$UNSIGNED"
scenario "3. Reference par tag"                    1 env OUT_DIR=out/tag      ./verify/verify.sh "$TAGREF"

echo; echo "${B}=== Bilan ===${N}"
printf '%s\n' "${RESULTS[@]}"
