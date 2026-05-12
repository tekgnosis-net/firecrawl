# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Firecrawl is a web scraper API. The directory you have access to is a monorepo:
 - `apps/api` — the API server, workers, scraper engines, and tests. **This is where almost all changes happen.**
 - `apps/api/native` — a Rust crate (`@mendable/firecrawl-rs`) consumed via N-API; built as part of `pnpm install`.
 - `apps/api/sharedLibs/go-html-to-md` — Go service for HTML→markdown conversion, used in-process via FFI.
 - `apps/*-sdk` — language SDKs (Python, JS, Go, Rust, Java, Ruby, PHP, Elixir, .NET).
 - `apps/playwright-service-ts`, `apps/nuq-postgres`, `apps/redis`, `apps/test-site`, `apps/test-suite`, `apps/ui` — supporting services and tooling.

## Workflow for API changes

1. Write end-to-end tests that assert your win conditions, if they don't already exist.
  - 1 happy path (more is encouraged if there are multiple happy paths with significantly different code paths taken).
  - 1+ failure path(s).
  - Generally, E2E (called `snips` in the API) is always preferred over unit testing.
  - Snips live at `apps/api/src/__tests__/snips/v{0,1,2}/*.test.ts` — pick the version directory matching the endpoint you're touching. Import `scrapeTimeout`, `idmux`, `Identity` from the version-local `./lib` (which re-exports `../lib.ts`).
  - Always use `scrapeTimeout` from `./lib` to set the timeout you use for scrapes.
  - These tests are run on a variety of configurations. Gate tests in the following manner:
    - If it requires fire-engine: `!process.env.TEST_SUITE_SELF_HOSTED`
    - If it requires AI: `!process.env.TEST_SUITE_SELF_HOSTED || process.env.OPENAI_API_KEY || process.env.OLLAMA_BASE_URL`
2. Write code to achieve your win conditions.
3. Run your tests using `pnpm harness jest ...` from `apps/api`.
  - `pnpm harness` gets the API server and workers up for you to run the tests. Don't try to `pnpm start` manually.
  - The full test suite takes a long time to run, so only execute relevant tests locally and let CI run the full suite.
4. Push to a branch, open a PR, and let CI run to verify your win condition.

## Common commands

All commands run from `apps/api` unless noted otherwise.

| Command | Purpose |
|---|---|
| `pnpm install` (repo root) | Installs all workspaces. Builds the Rust native crate. |
| `pnpm harness` | Boots the full stack (API, all workers, nuq-postgres container) for local dev. Use this — not `pnpm start`. |
| `pnpm harness jest <pattern>` | Boots the stack and runs a specific test file/pattern. The preferred way to run any test locally. |
| `pnpm test:snips` | Runs all snip tests (matches `src/__tests__/snips/v[12]/.+\.test\.ts`). |
| `pnpm build` | TypeScript compile only (no tests). |
| `pnpm format` | Prettier-format `src/**/*.{js,ts}`. Runs automatically via husky on commit. |
| `pnpm knip` | Dead-code / unused-export scan. |

`docker compose up` from the repo root brings up Redis + API + workers via `docker-compose.yaml` — useful as an alternative to running the harness for non-dev scenarios.

## High-level architecture

### Runtime topology

The API is not a single process. `pnpm harness` orchestrates several:

- **API server** (`src/index.ts`) — Express + ws, terminates HTTP, validates with Zod, enqueues jobs, serves Bull-Board admin UI.
- **Queue worker** (`src/services/queue-worker.ts`) — BullMQ-backed worker for the main scrape/crawl pipeline (uses Redis).
- **Nuq workers** (`src/services/worker/nuq-worker.ts`, `nuq-prefetch-worker.ts`, `nuq-reconciler-worker.ts`) — a Postgres-backed queue (`apps/nuq-postgres`) for higher-durability work. "Nuq" = the in-house queue; see `apps/nuq-postgres/nuq.sql` for the schema.
- **Extract worker** (`src/services/extract-worker.ts`) — runs the LLM extraction pipeline.
- **Index worker** (`src/services/indexing/index-worker.ts`) — keeps the search index up to date.

External dependencies the harness/compose stack expects:
- **Redis** — BullMQ queues, rate limiting, redlock, ephemeral state.
- **Postgres** (`apps/nuq-postgres`) — durable queue + indexing.
- **Supabase** (optional) — auth, billing, structured logs. Tests gate on `USE_DB_AUTHENTICATION`.
- **fire-engine** (optional, proprietary) — the premium scrape backend. Tests requiring it must gate on `!process.env.TEST_SUITE_SELF_HOSTED`.
- **Playwright service** (`apps/playwright-service-ts`) — JS-rendering fallback when fire-engine isn't available.

### Request flow

`HTTP → routes/v{0,1,2}.ts → controllers/v{0,1,2}/<endpoint>.ts → queue (BullMQ or nuq) → worker → scraper → response`

`v0`, `v1`, `v2` are **parallel API surfaces that all coexist in prod.** When you add behavior, decide which version(s) it lands in — they have separate Zod types in `controllers/v{N}/types.ts`, separate controller handlers, and separate snips test folders. Cross-version helpers live in `routes/shared.ts` and `src/lib/`.

### The scrape engine (the part that requires reading multiple files)

`src/scraper/scrapeURL/` is the heart of the scraper. Key shape:

```
scrapeURL(url, options)
  → buildFallbackList()      // picks ordered list of engines based on URL + options
  → for each engine:
       scrapeURLWithEngine() // try this engine
       parseMarkdown()
       if successful → run postprocessors → return
       else → next engine
  → if all engines exhausted → NoEnginesLeftError
```

Engines live under `scraper/scrapeURL/engines/`:
- `fetch` — plain HTTP fetch (cheapest, no JS).
- `playwright` — calls the Playwright microservice.
- `fire-engine` — premium backend; multiple sub-variants (chrome, chrome-cdp, tlsclient, etc.).
- `pdf` — PDF parsing path (LlamaParse or local).
- `document` — DOCX/etc. via mammoth.
- `wikipedia`, `x-twitter` — site-specific fast paths.
- `index` — fetch from internal index cache.

Postprocessors and transformers (markdown, screenshots, JSON extract via LLM) sit in sibling folders. When a scrape misbehaves, the answer is almost always "which engine was selected, and why did its branch fail" — `engpicker.ts` in `src/lib/` is where the selection logic lives.

### Native code

- `apps/api/native` is a Rust crate exposed via N-API (`@mendable/firecrawl-rs` workspace package) — performance-critical bits (HTML parsing, ranking, etc.).
- `apps/api/sharedLibs/go-html-to-md` is a Go library called via `koffi` FFI (see `src/lib/html-to-markdown.ts`).

You generally don't need to touch these unless changing serialization at the boundary, but be aware they exist and are rebuilt by `pnpm install`.

## Conventions to follow

- **Don't add a unit test when a snip will do.** Snips are integration tests that hit the real API via the harness. They catch the bugs that matter.
- **Don't run `pnpm start` directly.** It boots only the API, not the workers — and most code paths require workers. Use `pnpm harness`.
- **`scrapeTimeout` is shared.** Don't invent ad-hoc timeouts in snips; import from `./lib`.
- **Version-scope changes deliberately.** A change to `/v2/scrape` does not automatically apply to `/v1/scrape`; the types and controllers are separate by design. If a fix should land in multiple versions, make that explicit.
- **Prettier auto-formats on commit** (lint-staged + husky). Don't fight it.
