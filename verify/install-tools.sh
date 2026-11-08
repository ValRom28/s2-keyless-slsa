#!/usr/bin/env bash
# Installe les outils de verification en versions figees, empreintes SHA-256 controlees.
# Usage : ./verify/install-tools.sh [dossier]   (defaut : ./bin)
set -euo pipefail

DEST="${1:-./bin}"
mkdir -p "$DEST"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]; then
  echo "Ce script cible Linux x86_64 (empreintes figees pour cette plateforme)." >&2
  exit 1
fi

fetch() { # url fichier sha256
  curl -sSfL --retry 3 -o "$WORK/$2" "$1"
  echo "$3  $WORK/$2" | sha256sum -c --quiet - || { echo "Empreinte invalide : $2" >&2; exit 1; }
}

fetch https://github.com/sigstore/cosign/releases/download/v3.1.4/cosign-linux-amd64 \
  cosign 424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa
fetch https://github.com/slsa-framework/slsa-verifier/releases/download/v2.7.0/slsa-verifier-linux-amd64 \
  slsa-verifier 499befb675efcca9001afe6e5156891b91e71f9c07ab120a8943979f85cc82e6
fetch https://github.com/open-policy-agent/conftest/releases/download/v0.71.1/conftest_0.71.1_Linux_x86_64.tar.gz \
  conftest.tgz c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985
fetch https://github.com/google/go-containerregistry/releases/download/v0.22.1/go-containerregistry_Linux_x86_64.tar.gz \
  crane.tgz 0ab7a1d6932a213aed964ce97666c3077fe691c8606413674a8b3e0b9ec4cda0

tar -xzf "$WORK/conftest.tgz" -C "$WORK" conftest
tar -xzf "$WORK/crane.tgz" -C "$WORK" crane
install -m 0755 "$WORK/cosign" "$WORK/slsa-verifier" "$WORK/conftest" "$WORK/crane" "$DEST/"

echo "Outils installes dans $DEST :"
"$DEST/cosign" version 2>/dev/null | grep GitVersion
"$DEST/slsa-verifier" version 2>/dev/null | grep GitVersion
"$DEST/conftest" --version | head -1
echo "crane $("$DEST/crane" version)"
