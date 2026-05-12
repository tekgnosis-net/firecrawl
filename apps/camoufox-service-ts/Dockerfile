FROM node:20-slim

# `git` is required because we pull camoufox-js directly from GitHub
# (`github:apify/camoufox-js` in package.json) — npm spawns `git clone`
# under the hood, which is missing from the slim base image.
RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
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
