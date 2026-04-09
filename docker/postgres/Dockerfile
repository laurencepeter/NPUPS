# ──────────────────────────────────────────────────────────────────────────────
# NPUPS Custom PostgreSQL Image
# Extends the official postgres:16 image with the pgjwt extension.
# pgjwt: https://github.com/michelp/pgjwt
# Requires: pgcrypto (bundled with PostgreSQL)
# ──────────────────────────────────────────────────────────────────────────────

FROM postgres:16

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      make \
      gcc \
      postgresql-server-dev-16 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/michelp/pgjwt.git /tmp/pgjwt \
    && cd /tmp/pgjwt \
    && make install \
    && rm -rf /tmp/pgjwt

# Copy SQL init scripts — Postgres runs these in filename order on first start
COPY init/ /docker-entrypoint-initdb.d/
