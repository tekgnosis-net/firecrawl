import Redlock from "redlock";
import { config } from "../config";
import Client from "ioredis";
import { logger } from "../lib/logger";

// Redlock holds its own ioredis Client. Like every other ioredis instance,
// it needs an 'error' listener — without one, ioredis reply errors surface
// as "[ioredis] Unhandled error event: ..." stderr spam (and on Node >= 15,
// an unhandled 'error' event throws on the next tick).
const redlockClient = new Client(config.REDIS_RATE_LIMIT_URL!);
redlockClient.on("error", err => {
  try {
    logger.error("Redlock Redis client error", { err });
  } catch {}
});

export const redlock = new Redlock(
  // You should have one client for each independent redis node
  // or cluster.
  [redlockClient],
  {
    // The expected clock drift; for more details see:
    // http://redis.io/topics/distlock
    driftFactor: 0.01, // multiplied by lock ttl to determine drift time

    retryCount: 200,

    retryDelay: 100,

    // the max time in ms randomly added to retries
    // to improve performance under high contention
    // see https://www.awsarchitectureblog.com/2015/03/backoff.html
    retryJitter: 200, // time in ms

    // The minimum remaining time on a lock before an extension is automatically
    // attempted with the `using` API.
    automaticExtensionThreshold: 500, // time in ms
  },
);
