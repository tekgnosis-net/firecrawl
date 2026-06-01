FROM node:20-slim

# ca-certificates is needed for the HTTPS download of the Camoufox binary
# (`npx camoufox-js fetch`, below) — node:*-slim ships without it.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
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
