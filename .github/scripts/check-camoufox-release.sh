#!/usr/bin/env bash
#
# Detect when a newer camoufox-js is published than the one pinned in
# apps/camoufox-service-ts/package.json. Emits GITHUB_OUTPUT for the workflow
# to decide whether to open a tracking issue.
#
# camoufox-js is the only thing we pin directly; the Camoufox *browser* binary
# is fetched transitively by `camoufox-js fetch` at image-build time, so the
# library version is the actionable signal for staying current with upstream.
#
# GITHUB_OUTPUT:
#   pinned=<x.y.z>   latest=<x.y.z>   update=true|false
#
# Deps: curl, jq, sort -V (all preinstalled on ubuntu-latest runners).
set -euo pipefail

PKG="apps/camoufox-service-ts/package.json"
emit() { echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/stdout}"; }

PINNED="$(jq -r '.dependencies["camoufox-js"]' "$PKG")"
LATEST="$(curl -fsSL https://registry.npmjs.org/camoufox-js/latest | jq -r .version)"

emit pinned "$PINNED"
emit latest "$LATEST"
echo "camoufox-js pinned=${PINNED} latest=${LATEST}"

if [ -z "$LATEST" ] || [ "$LATEST" = "null" ]; then
  echo "::warning:: could not resolve latest camoufox-js from npm registry"
  emit update false
  exit 0
fi

if [ "$PINNED" = "$LATEST" ]; then
  echo "Up to date."
  emit update false
  exit 0
fi

# Only flag when latest is genuinely newer than the pin (guard against a pin
# that is somehow ahead of the dist-tag).
NEWER="$(printf '%s\n%s\n' "$PINNED" "$LATEST" | sort -V | tail -1)"
if [ "$NEWER" = "$PINNED" ]; then
  echo "Pinned (${PINNED}) is >= latest (${LATEST}); nothing to do."
  emit update false
  exit 0
fi

echo "Update available: ${PINNED} -> ${LATEST}"
emit update true
