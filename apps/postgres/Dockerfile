# syntax=docker/dockerfile:1

FROM postgres:17

ARG POSTGRES_VERSION

ARG SUPERCRONIC_VERSION
# renovate: datasource=github-releases depName=EnterpriseDB/system_stats
ARG SYSTEM_STATS_EXTENSION_VERSION="3.2"
# renovate: datasource=github-releases depName=tensorchord/VectorChord
ARG VCHORD_EXTENSION_VERSION="0.4.3"

ENV TZ="Asia/Kolkata"

RUN DEBIAN_FRONTEND=noninteractive apt update \
    && apt install -y --no-install-recommends \
    postgresql-server-dev-${POSTGRES_VERSION} \
    jq \
    wget \
    bash \
    pgbackrest \
    ca-certificates \
    postgresql-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN cp /usr/share/zoneinfo/${TZ} /etc/localtime
RUN echo "${TZ}" > /etc/timezone

COPY . /
RUN chmod +x /entrypoint.sh

# Download and install SuperCronic for linux-amd64 (latest release)
RUN wget -O /usr/local/bin/supercronic "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" \
    && chmod +x /usr/local/bin/supercronic

# Install extension
RUN wget -O /tmp/system_stats.tar.gz https://github.com/EnterpriseDB/system_stats/archive/refs/tags/v${SYSTEM_STATS_EXTENSION_VERSION}.tar.gz \
    && cd /tmp/ && tar -zxvf system_stats.tar.gz \
    && cd system_stats-${SYSTEM_STATS_EXTENSION_VERSION} \
    && PATH="/usr/local/pgsql/bin:$PATH" make USE_PGXS=1 \
    && PATH="/usr/local/pgsql/bin:$PATH" make install USE_PGXS=1

RUN wget -O /tmp/vchord.deb https://github.com/tensorchord/VectorChord/releases/download/${VCHORD_EXTENSION_VERSION}/postgresql-17-vchord_${VCHORD_EXTENSION_VERSION}-1_$(dpkg --print-architecture).deb \
    && apt install /tmp/vchord.deb

ENTRYPOINT ["/entrypoint.sh"]

STOPSIGNAL SIGINT

CMD ["postgres"]
