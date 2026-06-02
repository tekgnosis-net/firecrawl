import { Counter } from "prom-client";

// Camoufox is a specialty stealth engine: it only runs after the normal engines
// escalate via `stealthProxy` (e.g. playwright got 401/403/429). So its own
// outcome is a direct stealth-efficacy signal — a rising `blocked` rate means
// the patched browser is no longer evading bot protection, most likely after a
// camoufox-js / browser bump. The smoke gate proves the image launches and
// renders; it CANNOT prove stealth still works from a CI IP. This metric is the
// safeguard that does.
//
// Registered on the default prom-client registry on import, so it surfaces on
// the worker /metrics endpoints (nuq-worker / extract-worker) alongside the
// other firecrawl_* metrics — the same place a scrape job runs the engine.
//
// Suggested Prometheus alert (template in
// examples/kubernetes/monitoring/camoufox-stealth-alerts.yaml):
//
//   - alert: CamoufoxStealthRegression
//     expr: |
//       sum(rate(firecrawl_camoufox_scrape_total{outcome="blocked"}[1h]))
//         /
//       clamp_min(sum(rate(firecrawl_camoufox_scrape_total[1h])), 1) > 0.4
//     for: 30m
//
// Break down by `status_code` to distinguish 403 (fingerprint block) from 429
// (rate limit) — they call for different responses.

export type CamoufoxOutcome = "success" | "blocked" | "error";

export const camoufoxScrapeTotal = new Counter({
  name: "firecrawl_camoufox_scrape_total",
  help: "Camoufox stealth-engine scrape outcomes by result and HTTP status; a rising 'blocked' (401/403/429) rate signals a stealth regression",
  labelNames: ["outcome", "status_code"],
});

// Classify the page status code the Camoufox service returns for the target.
export function classifyCamoufoxOutcome(statusCode: number): CamoufoxOutcome {
  if (statusCode >= 200 && statusCode < 300) return "success";
  if (statusCode === 401 || statusCode === 403 || statusCode === 429) {
    return "blocked";
  }
  return "error";
}
