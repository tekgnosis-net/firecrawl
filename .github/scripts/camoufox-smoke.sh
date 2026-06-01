#!/usr/bin/env bash
#
# Smoke-test a built Camoufox service image before it is allowed to ship.
# Boots the container and asserts the things a broken camoufox-js bump would
# break: (1) the browser actually launches (/health), (2) a real page renders
# (/scrape), (3) the SSRF guard still refuses internal targets.
#
# IMPORTANT: /scrape returns HTTP 200 even on failure and puts the real status
# in the body's `pageStatusCode` — so we assert the BODY, not the HTTP code.
#
# This proves launch + render, NOT stealth efficacy (example.com is static).
#
# Usage: IMAGE=ghcr.io/.../camoufox-service:canary bash .github/scripts/camoufox-smoke.sh
set -euo pipefail

IMAGE="${IMAGE:?set IMAGE to the image ref to smoke}"
PORT="${PORT:-3001}"
NAME="camoufox-smoke-$$"
BASE="http://localhost:${PORT}"

cleanup() {
  echo "::group::camoufox container logs"
  docker logs "$NAME" 2>&1 | tail -100 || true
  echo "::endgroup::"
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Booting ${IMAGE} ..."
docker run -d --name "$NAME" -p "${PORT}:${PORT}" "$IMAGE" >/dev/null

# 1) Health — /health launches a real Camoufox browser, so allow warmup time.
echo "Waiting for /health to report healthy ..."
healthy=0
for i in $(seq 1 36); do
  body="$(curl -fsS "${BASE}/health" 2>/dev/null || true)"
  if [ -n "$body" ] && [ "$(printf '%s' "$body" | jq -r '.status' 2>/dev/null)" = "healthy" ]; then
    echo "healthy after ~$((i * 5))s: ${body}"
    healthy=1
    break
  fi
  sleep 5
done
[ "$healthy" = 1 ] || { echo "FAIL: /health never reported healthy"; exit 1; }

# 2) Real scrape — assert the BODY's pageStatusCode, not the HTTP status.
echo "Scraping https://example.com ..."
resp="$(curl -fsS -X POST "${BASE}/scrape" -H 'content-type: application/json' \
  -d '{"url":"https://example.com"}')"
ps="$(printf '%s' "$resp" | jq -r '.pageStatusCode')"
err="$(printf '%s' "$resp" | jq -r '.pageError // empty')"
len="$(printf '%s' "$resp" | jq -r '.content | length')"
echo "pageStatusCode=${ps} contentLength=${len} pageError='${err}'"
[ "$ps" = "200" ] || { echo "FAIL: expected pageStatusCode 200, got ${ps}"; exit 1; }
[ -z "$err" ] || { echo "FAIL: unexpected pageError: ${err}"; exit 1; }
printf '%s' "$resp" | jq -e '.content | test("Example Domain")' >/dev/null \
  || { echo "FAIL: scraped content did not contain 'Example Domain'"; exit 1; }

# 3) SSRF guard — an internal target must be refused with pageStatusCode 403.
echo "Verifying SSRF guard blocks http://localhost ..."
sresp="$(curl -fsS -X POST "${BASE}/scrape" -H 'content-type: application/json' \
  -d '{"url":"http://localhost"}')"
sps="$(printf '%s' "$sresp" | jq -r '.pageStatusCode')"
[ "$sps" = "403" ] || { echo "FAIL: SSRF guard broken — expected 403, got ${sps}"; exit 1; }

echo "PASS: Camoufox smoke (health + real scrape + SSRF guard)."
