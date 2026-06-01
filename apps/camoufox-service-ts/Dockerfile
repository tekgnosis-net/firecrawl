FROM node:20-slim

# ca-certificates: HTTPS download of the Camoufox binary (`camoufox-js fetch`).
# build-essential + python3: node-gyp needs them to compile better-sqlite3 (a
# transitive camoufox-js dep) from source — node:*-slim has no toolchain, and
# no prebuilt binary is published for this platform/node combo, so npm install
# falls back to a source build.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates build-essential python3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install

# Install system dependencies for Firefox (Camoufox is a Firefox fork).
# We use Playwright's install-deps subcommand to grab the right packages
# without downloading Playwright's own firefox binary.
RUN npx playwright install-deps firefox

# Download the Camoufox patched Firefox binary into the image so first
# launch doesn't have to fetch ~200 MB over the network.
RUN npx camoufox-js fetch

COPY . .
RUN npm run build

ARG PORT
ENV PORT=${PORT}

EXPOSE ${PORT}

CMD [ "npm", "start" ]
