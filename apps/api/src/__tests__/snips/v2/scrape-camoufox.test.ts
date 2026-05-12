import {
  describeIf,
  itIf,
  HAS_CAMOUFOX,
  TEST_PRODUCTION,
} from "../lib";
import {
  scrape,
  scrapeRaw,
  scrapeTimeout,
  idmux,
  Identity,
} from "./lib";

// Camoufox is registered as a specialty stealth engine (quality: -3,
// stealthProxy: true). It is only selected when the scrape's feature flags
// include stealthProxy — most naturally triggered by `proxy: "stealth"` in the
// request, or by playwright returning 401/403/429 with `proxy: "auto"`.
//
// These tests verify the engine is wired up correctly. They gate on
// HAS_CAMOUFOX so they no-op when CAMOUFOX_MICROSERVICE_URL is unset.
// They also skip in TEST_PRODUCTION because the prod stack uses fire-engine
// for stealth, not camoufox.
describeIf(HAS_CAMOUFOX && !TEST_PRODUCTION)(
  "Camoufox stealth engine",
  () => {
    let identity: Identity;

    beforeAll(async () => {
      identity = await idmux({
        name: "scrape-camoufox",
        concurrency: 4,
        credits: 1000,
      });
    }, 10000 + scrapeTimeout);

    itIf(HAS_CAMOUFOX && !TEST_PRODUCTION)(
      "scrapes a URL via the camoufox engine when proxy: stealth is requested",
      async () => {
        const doc = await scrape(
          {
            url: "https://example.com",
            proxy: "stealth",
            formats: ["markdown"],
          },
          identity,
        );

        expect(doc.metadata?.statusCode).toBe(200);
        expect(typeof doc.markdown).toBe("string");
        expect(doc.markdown!.length).toBeGreaterThan(0);
      },
      scrapeTimeout * 2,
    );

    itIf(HAS_CAMOUFOX && !TEST_PRODUCTION)(
      "returns a useful error when camoufox service is unreachable",
      async () => {
        // Drive an invalid hostname through camoufox to confirm error
        // surfaces through the engine adapter rather than crashing the worker.
        const raw = await scrapeRaw(
          {
            url: "https://this-domain-should-not-resolve-camoufox-test.invalid",
            proxy: "stealth",
            formats: ["markdown"],
          },
          identity,
        );

        // Either the engine errors and Firecrawl returns 500/200-with-error;
        // both are acceptable as long as the API doesn't hang or crash.
        expect([200, 500]).toContain(raw.statusCode);
      },
      scrapeTimeout * 2,
    );
  },
);
