#!/usr/bin/env bash
#
# Sync this fork with upstream firecrawl/firecrawl.
#
# Strategy: MERGE upstream/<branch> into a fresh sync branch cut from
# origin/<base>, auto-resolving ONLY the single deterministic conflict class
# this fork creates — workflow / SDK files we intentionally deleted that
# upstream still modifies (a "modify/delete, deleted by us" conflict). Any
# other conflict, or a failing build, aborts for a human to handle.
#
# The build gate (tsc) is deliberately included: this fork dropped the upstream
# PR test workflows, so it is the only automated signal that an otherwise-clean
# textual merge did not introduce type drift (e.g. a new upstream FeatureFlag).
#
# Exit codes / GITHUB_OUTPUT `result`:
#   0  result=uptodate  nothing to merge
#   0  result=ready     merged (auto-resolved if needed) + build passed, pushed
#   2  result=conflict  non-deterministic conflict — human needed
#   2  result=buildfail merge applied but tsc failed — human needed
#
# Env overrides: UPSTREAM_URL, UPSTREAM_BRANCH, BASE_BRANCH, RUN_BUILD (0 to skip).
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/firecrawl/firecrawl.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
BASE_BRANCH="${BASE_BRANCH:-main}"
RUN_BUILD="${RUN_BUILD:-1}"

emit() { echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/stdout}"; }

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
git fetch upstream --prune
git fetch origin --prune

UP_SHA="$(git rev-parse --short "upstream/${UPSTREAM_BRANCH}")"
BRANCH="automation/upstream-sync-${UP_SHA}"

# Already integrated? Then there is nothing to do.
if git merge-base --is-ancestor "upstream/${UPSTREAM_BRANCH}" "origin/${BASE_BRANCH}"; then
  echo "Already up to date with upstream ${UP_SHA}."
  emit result uptodate
  exit 0
fi

git switch -C "$BRANCH" "origin/${BASE_BRANCH}"

if ! git merge --no-edit --no-ff "upstream/${UPSTREAM_BRANCH}"; then
  # Resolve ONLY "deleted by us" (DU/DD) paths by keeping them deleted.
  # Anything else is a real semantic conflict and must stop for a human.
  while IFS= read -r line; do
    code="${line:0:2}"; path="${line:3}"
    case "$code" in
      DU|DD) git rm -- "$path" >/dev/null ;;
      *)     echo "::warning:: unresolved conflict (${code}): ${path}" ;;
    esac
  done < <(git status --porcelain | grep -E '^(DD|AU|UD|UA|DU|AA|UU)' || true)

  if git status --porcelain | grep -qE '^(DD|AU|UD|UA|DU|AA|UU)'; then
    emit result conflict
    exit 2
  fi
  git commit --no-edit
fi

# Build gate — the only automated correctness signal on this fork.
if [ "$RUN_BUILD" = "1" ]; then
  ( cd apps/api && pnpm install --frozen-lockfile && pnpm build ) || { emit result buildfail; exit 2; }
fi

git push -u origin "$BRANCH" --force-with-lease
emit result ready
emit branch "$BRANCH"
echo "Sync branch ${BRANCH} pushed and ready for PR."
