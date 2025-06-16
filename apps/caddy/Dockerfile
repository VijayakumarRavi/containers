# syntax=docker/dockerfile:1
ARG VERSION
# Build stage
FROM caddy:${VERSION}-builder-alpine AS builder

# Build Caddy with the Cloudflare DNS module
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/greenpau/caddy-security

# Final stage
FROM caddy:${VERSION}-alpine

COPY defaults/Caddyfile /etc/caddy/Caddyfile
COPY defaults/index.html /srv/index.html

# Copy the custom-built Caddy binary
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
