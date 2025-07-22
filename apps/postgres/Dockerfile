# syntax=docker/dockerfile:1
ARG POSTGRES_VERSION

FROM postgres:${POSTGRES_VERSION:-17}

ARG SUPERCRONIC_VERSION

ENV TZ="Asia/Kolkata"

RUN DEBIAN_FRONTEND=noninteractive apt update \
        && apt install -y --no-install-recommends \
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

ENTRYPOINT ["/entrypoint.sh"]

STOPSIGNAL SIGINT

CMD ["postgres"]
