#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# Bootstrap script — runs on first container start.
# Applies schema, auth, and seed data to the NPUPS database.
# PostgreSQL init scripts run as the superuser inside the container.
# ──────────────────────────────────────────────────────────────────────────────
set -e

DB="${POSTGRES_DB:-npups}"

# Set the JWT secret as a Postgres config parameter so the login() function
# can read it via current_setting('app.jwt_secret')
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB" <<-EOSQL
  ALTER DATABASE "${DB}" SET app.jwt_secret = '${NPUPS_JWT_SECRET}';
EOSQL

echo "JWT secret configured for database: ${DB}"

# Apply authenticator password from env
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB" <<-EOSQL
  DO \$\$
  BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
      ALTER ROLE authenticator PASSWORD '${POSTGREST_DB_PASSWORD}';
    END IF;
  END
  \$\$;
EOSQL
