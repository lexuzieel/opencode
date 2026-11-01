#!/bin/bash
# Install Authelia from the templates in this directory.
# Usage: ./setup.sh [PASSWORD]
#   PASSWORD  web login password (generated when omitted)
# Refuses to touch an existing config unless FORCE=1 is set.
# Writes config/, data/ and authelia-login.txt next to compose.yaml, then
# starts the container on the docker "gateway" network.
#
# Environment:
#   AUTHELIA_USER    login name (default: aleksei)
#   AUTHELIA_DOMAIN  mail and cookie domain (default: aleksei.dev)
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGE="authelia/authelia:latest"
USERNAME="${AUTHELIA_USER:-aleksei}"
DOMAIN="${AUTHELIA_DOMAIN:-aleksei.dev}"

cd "$HERE"
[ -f compose.yaml ] || { echo "error: compose.yaml missing" >&2; exit 1; }
[ -f configuration.yml.example ] || { echo "error: configuration.yml.example missing" >&2; exit 1; }

if [ -f config/configuration.yml ] && [ "${FORCE:-0}" != "1" ]; then
    echo "error: config/configuration.yml exists; set FORCE=1 to overwrite" >&2
    exit 1
fi

docker network inspect gateway >/dev/null 2>&1 || docker network create gateway

PASSWORD="${1:-}"
if [ -z "$PASSWORD" ]; then
    PASSWORD="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-24)"
fi

echo "== hashing the password"
HASH="$(docker run --rm --entrypoint /app/authelia "$IMAGE" \
    crypto hash generate argon2 --password "$PASSWORD" | sed -n 's/^Digest: //p')"
case "$HASH" in
    \$argon2*) ;;
    *) echo "error: could not generate an argon2 hash" >&2; exit 1 ;;
esac

echo "== writing config"
mkdir -p config data
sed -e "s|__GENERATED__|$(openssl rand -base64 48 | tr -d '\n')|" \
    -e "s|<domain>|$DOMAIN|g" \
    configuration.yml.example > config/configuration.yml
sed -e "s|'__SET_BY_SETUP__'|'$HASH'|" \
    -e "s|__USER__|$USERNAME|g" \
    -e "s|<domain>|$DOMAIN|g" \
    users_database.yml.example > config/users_database.yml

# The official image runs as root, so no uid mapping is needed here. The files
# stay 600 and the directories 700 for the host user.
printf '# Authelia portal: https://auth.%s\n# login: %s\npassword: %s\n' \
    "$DOMAIN" "$USERNAME" "$PASSWORD" > authelia-login.txt
chmod 700 config data
chmod 600 config/configuration.yml config/users_database.yml authelia-login.txt

echo "== validating"
docker run --rm -v "$HERE/config:/config" --entrypoint /app/authelia "$IMAGE" validate-config

echo "== starting"
# The image chowns /config to PUID:PGID on start, so record the host user in
# the compose .env: without it the container owns the config as root.
[ -f .env ] || printf 'PUID=%s\nPGID=%s\n' "$(id -u)" "$(id -g)" > .env
docker compose up -d
sleep 3
docker compose ps --format '{{.Name}} {{.Status}}'
echo
echo "login written to $HERE/authelia-login.txt (user: $USERNAME)"
echo "next: point the proxy host at http://authelia:9091, then guard hosts with"
echo "      ./guard.sh protect <npm-host-id> (needs NPM_URL, NPM_IDENTITY,"
echo "      NPM_SECRET, AUTH_DOMAIN in the environment)."
