# Bitnami yanked all free tags from Docker Hub in August 2025, so we use
# the official Redis image instead. The Debian-based variant (not alpine)
# is required because start-redis-server.sh is a bash script.
ARG REDIS_VERSION=8
FROM redis:${REDIS_VERSION}

COPY start-redis-server.sh /usr/bin/start-redis-server.sh
RUN chmod +x /usr/bin/start-redis-server.sh

CMD ["/usr/bin/start-redis-server.sh"]
