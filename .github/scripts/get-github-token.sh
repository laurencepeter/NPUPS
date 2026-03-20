#!/usr/bin/env bash
# Fetch a GitHub App installation access token with retry logic.
# Resolves: cURL error 28 (connection timeout) on api.github.com
#
# Usage: ./get-github-token.sh <installation_id> <app_id> <private_key_path>

set -euo pipefail

INSTALLATION_ID="${1:?Usage: $0 <installation_id> <app_id> <private_key_path>}"
APP_ID="${2:?Usage: $0 <installation_id> <app_id> <private_key_path>}"
PRIVATE_KEY_PATH="${3:?Usage: $0 <installation_id> <app_id> <private_key_path>}"

MAX_RETRIES=5
RETRY_DELAY=2
CONNECT_TIMEOUT=30   # seconds before giving up on connection
MAX_TIME=60          # total maximum time per request in seconds

# Generate a JWT for GitHub App authentication
generate_jwt() {
  local now
  local exp
  local header
  local payload
  local signature

  now=$(date +%s)
  exp=$((now + 600))  # 10-minute expiry

  header=$(printf '{"alg":"RS256","typ":"JWT"}' | base64 -w0 | tr '+/' '-_' | tr -d '=')
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$now" "$exp" "$APP_ID" \
    | base64 -w0 | tr '+/' '-_' | tr -d '=')

  signature=$(printf '%s.%s' "$header" "$payload" \
    | openssl dgst -sha256 -sign "$PRIVATE_KEY_PATH" \
    | base64 -w0 | tr '+/' '-_' | tr -d '=')

  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

fetch_token() {
  local jwt
  jwt=$(generate_jwt)

  curl \
    --silent \
    --show-error \
    --fail \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    --retry 0 \
    --header "Authorization: Bearer $jwt" \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --request POST \
    "https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens"
}

ATTEMPT=0
while [ $ATTEMPT -lt $MAX_RETRIES ]; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "Fetching GitHub installation token (attempt $ATTEMPT of $MAX_RETRIES)..." >&2

  if RESPONSE=$(fetch_token 2>&1); then
    echo "Token fetched successfully." >&2
    echo "$RESPONSE"
    exit 0
  fi

  EXIT_CODE=$?
  echo "Attempt $ATTEMPT failed (exit code $EXIT_CODE): $RESPONSE" >&2

  if [ $ATTEMPT -lt $MAX_RETRIES ]; then
    echo "Retrying in ${RETRY_DELAY}s..." >&2
    sleep $RETRY_DELAY
    RETRY_DELAY=$((RETRY_DELAY * 2))
  fi
done

echo "ERROR: Failed to fetch GitHub installation token after $MAX_RETRIES attempts." >&2
exit 1
