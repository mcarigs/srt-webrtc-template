#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log_info() {
  echo "[INFO] $*"
}

log_ok() {
  echo "[OK] $*"
}

log_error() {
  echo "[ERROR] $*" >&2
}

echo "======================================================================================================"
echo "                              SRT Access Key Rotation"
echo "======================================================================================================"

if [[ ! -f .env ]]; then
  log_error ".env was not found. Run deploy.sh first."
  exit 1
fi

if [[ ! -f mediamtx.yml ]]; then
  log_error "mediamtx.yml was not found."
  exit 1
fi

if [[ ! -f generated/mediamtx.yml || ! -f generated/portal-config.js ]]; then
  log_error "Generated configuration was not found. Run deploy.sh first."
  exit 1
fi

if ! docker inspect -f '{{.State.Running}}' stream-mediamtx 2>/dev/null | grep -q '^true$'; then
  log_error "stream-mediamtx is not currently running."
  log_error "Start the deployment normally before rotating keys."
  exit 1
fi

set -a
source .env
set +a

if [[ -z "${DOMAIN:-}" ]]; then
  log_error "DOMAIN is missing from .env."
  exit 1
fi

log_info "Generating new SRT access keys..."

NEW_PUBLISH_KEY="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
NEW_HOST_KEY="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"

set_env_value() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

set_env_value "PUBLISH_KEY" "$NEW_PUBLISH_KEY"
set_env_value "HOST_KEY" "$NEW_HOST_KEY"

chmod 600 .env

TMP_MEDIAMTX="$(mktemp)"

cleanup() {
  rm -f "$TMP_MEDIAMTX"
}

trap cleanup EXIT

sed \
  -e "s/__DOMAIN__/${DOMAIN}/g" \
  -e "s/__PUBLISH_KEY__/${NEW_PUBLISH_KEY}/g" \
  -e "s/__HOST_KEY__/${NEW_HOST_KEY}/g" \
  mediamtx.yml > "$TMP_MEDIAMTX"


cat "$TMP_MEDIAMTX" > generated/mediamtx.yml

cat > generated/portal-config.js <<EOF
window.PortalConfig = {
  publishUser: "publisher",
  publishKey: "${NEW_PUBLISH_KEY}",
  hostUser: "host",
  hostKey: "${NEW_HOST_KEY}"
};
EOF

log_ok "New keys generated and configuration updated."

echo ""
log_info "Restarting MediaMTX only..."

docker restart stream-mediamtx >/dev/null

if docker inspect -f '{{.State.Running}}' stream-mediamtx 2>/dev/null | grep -q '^true$'; then
  log_ok "MediaMTX restarted successfully."
else
  log_error "MediaMTX failed to restart."
  exit 1
fi

echo ""
log_ok "SRT access keys rotated successfully."
echo ""
echo "All previous SRT publish/read URLs are now invalid."
echo "The protected setup pages now contain the new URLs."
echo "The website and Nginx were not restarted."
echo "======================================================================================================"