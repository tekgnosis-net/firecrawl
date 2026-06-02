import { z } from "zod";
import { config } from "../../../../config";
import { EngineScrapeResult } from "..";
import { Meta } from "../..";
import { robustFetch } from "../../lib/fetch";
import { getInnerJson } from "@mendable/firecrawl-rs";
import { camoufoxScrapeTotal, classifyCamoufoxOutcome } from "./metrics";

export async function scrapeURLWithCamoufox(
  meta: Meta,
): Promise<EngineScrapeResult> {
  const response = await robustFetch({
    url: config.CAMOUFOX_MICROSERVICE_URL!,
    headers: {
      "Content-Type": "application/json",
    },
    body: {
      url: meta.rewrittenUrl ?? meta.url,
      wait_after_load: meta.options.waitFor,
      timeout: meta.abort.scrapeTimeout(),
      headers: meta.options.headers,
      skip_tls_verification: meta.options.skipTlsVerification,
    },
    method: "POST",
    logger: meta.logger.child("scrapeURLWithCamoufox/robustFetch"),
    schema: z.object({
      content: z.string(),
      pageStatusCode: z.number(),
      pageError: z.string().optional(),
      contentType: z.string().optional(),
    }),
    mock: meta.mock,
    abort: meta.abort.asSignal(),
  });

  if (response.contentType?.includes("application/json")) {
    response.content = await getInnerJson(response.content);
  }

  // Record the stealth outcome — a rising "blocked" rate flags a regression.
  camoufoxScrapeTotal.inc({
    outcome: classifyCamoufoxOutcome(response.pageStatusCode),
    status_code: String(response.pageStatusCode),
  });

  return {
    url: meta.rewrittenUrl ?? meta.url,
    html: response.content,
    statusCode: response.pageStatusCode,
    error: response.pageError,
    contentType: response.contentType,

    proxyUsed: "stealth",
  };
}

export function camoufoxMaxReasonableTime(meta: Meta): number {
  // Firefox-based, heavier than Chromium — give it more headroom than the
  // 30s default used by the playwright engine.
  return (meta.options.waitFor ?? 0) + 45000;
}
