# Camoufox Scrape API

Stealth variant of the Playwright Scrape API. Exposes the same HTTP contract as
`apps/playwright-service-ts`, but renders pages with Camoufox — a custom
Firefox fork that patches anti-bot fingerprinting at the C++ level — via the
experimental `camoufox-js` package.

The Camoufox binary is **bundled into the Docker image** at build time
(`npx camoufox-js fetch`), so the container is fully self-contained.

## Environment

- `PORT` (default `3001`): HTTP listen port.
- `PROXY_SERVER`, `PROXY_USERNAME`, `PROXY_PASSWORD`: optional outbound proxy.
- `ALLOW_LOCAL_WEBHOOKS`: set `True` to disable SSRF guard for local targets.
- `BLOCK_MEDIA`: set `True` to abort `*.png/jpg/mp4/...` requests.
- `MAX_CONCURRENT_PAGES` (default `10`): per-instance page semaphore.

## Wire into Firecrawl

Set `CAMOUFOX_MICROSERVICE_URL=http://camoufox-service:3001/scrape` in the API
server's environment. The Firecrawl engine registry will pick it up
automatically (see `apps/api/src/scraper/scrapeURL/engines/camoufox/`).

Camoufox is registered as a **specialty stealth engine** (`quality: -3`,
`stealthProxy: true`). It is selected only when the scrape's feature flags
include `stealthProxy` — most naturally when the request body contains
`proxy: "stealth"`, or when the regular Playwright engine returns a
401/403/429 and the scrape loop escalates via `AddFeatureError`.

## Run locally

```bash
npm install
npx camoufox-js fetch    # downloads the patched Firefox (~200 MB)
npm run dev
```
