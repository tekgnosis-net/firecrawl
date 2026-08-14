# ---------- build stage: toolchain + compile native deps + tsc ----------
# node >= 22 required since camoufox-js 0.12.0: its better-sqlite3 ^13 dep
# ships prebuilt binaries that segfault node 20 at require-time (engines
# says >= 22, but npm ci only warns). Keep both stages on the same major.
FROM node:22-slim AS build

# build-essential + python3: node-gyp fallback for any native dep that lacks
# a prebuilt for this platform. They live ONLY in this stage and never reach
# the runtime image.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates build-essential python3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Reproducible install from the committed package-lock.json.
COPY package*.json ./
RUN npm ci

# Compile TypeScript -> dist/, then strip dev dependencies so only the runtime
# closure (incl. the compiled better-sqlite3 .node) carries to the next stage.
COPY . .
RUN npm run build \
  && npm prune --omit=dev

# ---------- runtime stage: slim, no compiler toolchain ----------
FROM node:22-slim

# ca-certificates: HTTPS download of the Camoufox binary (`camoufox-js fetch`).
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Production dependencies only (with the compiled better-sqlite3) from the build
# stage — no build-essential/python3, no dev deps, no TypeScript sources.
COPY --from=build /usr/src/app/node_modules ./node_modules

# Firefox system libraries (Camoufox is a Firefox fork). Playwright's
# install-deps grabs them without downloading Playwright's own browser binary.
RUN npx playwright install-deps firefox

# Bundle the Camoufox patched Firefox so first launch is offline (~200 MB).
RUN npx camoufox-js fetch

# Compiled app + manifest last, so editing source doesn't bust the heavy
# apt/fetch layers above.
COPY --from=build /usr/src/app/dist ./dist
COPY package.json ./

ARG PORT
ENV PORT=${PORT}

EXPOSE ${PORT}

CMD [ "npm", "start" ]
