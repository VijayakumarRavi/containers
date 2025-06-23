# syntax=docker/dockerfile:1

# Build stage
FROM caddy:2.10.0-builder-alpine AS builder

# Build Caddy with the Cloudflare DNS module
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/greenpau/caddy-security \
    --with github.com/mholt/caddy-l4/modules/l4tls \
    --with github.com/caddyserver/transform-encoder \
    --with github.com/mholt/caddy-l4/modules/l4proxy \
    --with github.com/mholt/caddy-l4/modules/l4proxyprotocol

# Final stage
FROM caddy:2.10.0-alpine

COPY defaults/Caddyfile /etc/caddy/Caddyfile
COPY defaults/index.html /srv/index.html

# Copy the custom-built Caddy binary
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
