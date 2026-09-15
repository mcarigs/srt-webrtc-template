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

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

echo "======================================================================================================"
echo "                      Zero-Latency SRT / WebRTC Restream Service - Deploy"
echo "======================================================================================================"

load_env() {
  if [[ -f .env ]]; then
    set -a
    source .env
    set +a
  fi
}

save_env() {
  cat > .env <<EOF
DOMAIN=${DOMAIN}
PUBLISH_KEY=${PUBLISH_KEY:-}
HOST_KEY=${HOST_KEY:-}
EOF

  chmod 600 .env
}

generate_stream_keys() {
  if [[ -z "${PUBLISH_KEY:-}" ]]; then
    PUBLISH_KEY="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
    log_ok "Generated new streamer publish key."
  fi

  if [[ -z "${HOST_KEY:-}" ]]; then
    HOST_KEY="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
    log_ok "Generated new host read key."
  fi

  save_env
}

validate_domain() {
  if [[ -z "${DOMAIN:-}" ]]; then
    log_error "DOMAIN is not set."
    exit 1
  fi

  # Only domain names and IPv4-style addresses are expected here.
  # Reject characters that should never appear in either.
  if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
    log_error "Invalid domain or IP address: ${DOMAIN}"
    exit 1
  fi

  if [[ "$DOMAIN" =~ ^[0-9.]+$ ]]; then
    log_warn "IP address detected instead of a domain name."
    log_warn "This deployment script currently configures HTTPS only for domain names."
    log_warn "The server will be configured in HTTP-only mode."
    USE_HTTP=true
  else
    USE_HTTP=false
  fi
}

prompt_domain() {
  if [[ -n "${DOMAIN:-}" ]]; then
    read -r -p "Use domain '${DOMAIN}' from .env? [Y/n]: " confirm
    confirm=${confirm:-Y}

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      DOMAIN=""
    fi
  fi

  if [[ -z "${DOMAIN:-}" ]]; then
    echo ""
    echo "A domain name or IP address is required."
    read -r -p "Enter your domain or IP (e.g. stream.example.com or 192.168.1.50): " DOMAIN
  fi

  validate_domain
  save_env
  log_ok "Using address: $DOMAIN"
}

render_configs() {
  mkdir -p generated

  if [ "$USE_HTTP" = true ]; then
    cat > generated/default.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    # Serve the public site
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
    }

    location ~ ^/(live|host-setup|streamer-setup)\.html$ {
        auth_basic "VIP Commentator Access";
        auth_basic_user_file /etc/nginx/.htpasswd;
        root /usr/share/nginx/html;
    }

    location = /portal-config.js {
        auth_basic "VIP Commentator Access";
        auth_basic_user_file /etc/nginx/.htpasswd;

        alias /etc/nginx/portal-config.js;
        default_type application/javascript;
    }

    # Proxy the MediaMTX WebRTC interface through the VIP login
    location /webrtc/ {
        auth_basic "VIP Commentator Access";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://127.0.0.1:8889/;
        proxy_redirect / /webrtc/;

        proxy_set_header Authorization "";
    }

    # Proxy the MediaMTX Control API through the VIP login
    location /api/ {
        auth_basic "VIP Commentator Access";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://127.0.0.1:9997/;
        proxy_redirect / /api/;

        proxy_set_header Authorization "";
    }
}
EOF

    log_ok "Generated HTTP-only Nginx config."
  else
    sed "s/__DOMAIN__/${DOMAIN}/g" \
      default.conf.template > generated/default.conf

    log_ok "Generated HTTPS Nginx config."
  fi

  sed \
    -e "s/__DOMAIN__/${DOMAIN}/g" \
    -e "s/__PUBLISH_KEY__/${PUBLISH_KEY}/g" \
    -e "s/__HOST_KEY__/${HOST_KEY}/g" \
    mediamtx.yml > generated/mediamtx.yml

  cat > generated/portal-config.js <<EOF
window.PortalConfig = {
  publishUser: "publisher",
  publishKey: "${PUBLISH_KEY}",
  hostUser: "host",
  hostKey: "${HOST_KEY}"
};
EOF

  log_ok "Generated MediaMTX and protected portal configuration."
}

if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
  log_info "Docker or Docker Compose is missing."
  log_info "Installing Docker environment..."

  sudo apt-get update
  sudo apt-get install -y docker.io docker-compose
  sudo systemctl enable docker
  sudo systemctl start docker

  log_ok "Docker installed successfully."
else
  log_ok "Docker and Docker Compose are already installed."
fi

load_env
prompt_domain
generate_stream_keys
render_configs

CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"

if [ "$USE_HTTP" = false ]; then
  if ! command -v certbot &> /dev/null; then
    log_info "Certbot is not installed. Installing Certbot..."

    sudo apt-get update
    sudo apt-get install -y certbot

    log_ok "Certbot installed successfully."
  fi

  if [[ ! -d "$CERT_DIR" ]]; then
    echo ""
    log_info "No TLS certificates found for ${DOMAIN}."
    log_info "Generating a new Let's Encrypt certificate..."

    docker-compose down 2>/dev/null || true

    read -r -p "Enter your email address for Let's Encrypt registration: " ssl_email

    if [[ -z "$ssl_email" ]]; then
      log_error "Email is required for certificate registration."
      exit 1
    fi

    sudo certbot certonly \
      --standalone \
      -d "$DOMAIN" \
      --non-interactive \
      --agree-tos \
      -m "$ssl_email"

    log_ok "TLS certificate generated for ${DOMAIN}."
  else
    echo ""
    log_ok "TLS certificate already exists at ${CERT_DIR}."
  fi

  echo ""
  log_info "Installing Certbot renewal hooks..."

  sudo install -D -m 755 \
    certbot/renewal-hooks/pre/10-stop-stream-web \
    /etc/letsencrypt/renewal-hooks/pre/10-stop-stream-web

  sudo install -D -m 755 \
    certbot/renewal-hooks/post/90-start-stream-web \
    /etc/letsencrypt/renewal-hooks/post/90-start-stream-web

  # Remove the old renewal hook if it was installed previously.
  sudo rm -f \
    /etc/letsencrypt/renewal-hooks/deploy/50-restart-mediamtx

  log_ok "Certbot renewal hooks installed."

  if sudo systemctl enable --now certbot.timer >/dev/null 2>&1; then
    log_ok "Certbot automatic renewal timer is enabled."
  else
    log_warn "Could not enable certbot.timer automatically."
    log_warn "Verify Certbot's automatic renewal scheduler after deployment."
  fi
else
  echo ""
  log_info "Running in HTTP-only mode. Skipping TLS certificate setup."
fi

if ! command -v htpasswd &> /dev/null; then
  log_info "Installing apache2-utils for commentator-room authentication..."

  sudo apt-get update
  sudo apt-get install -y apache2-utils

  log_ok "apache2-utils installed."
fi

if [[ ! -f .htpasswd ]]; then
  echo ""
  log_info "Setting up commentator-room authentication..."

  read -r -p "Enter a username for the live room [default: admin]: " input_user
  VIP_USER=${input_user:-admin}

  echo "Enter the password for user: $VIP_USER"
  htpasswd -c .htpasswd "$VIP_USER"

  log_ok "Password file created."
else
  log_ok "Password file (.htpasswd) already exists."
fi

echo ""
log_info "Starting Docker containers..."

docker-compose down 2>/dev/null || true
docker-compose up -d --force-recreate

echo ""
log_ok "Deployment complete."

if [ "$USE_HTTP" = true ]; then
  echo "Site:  http://${DOMAIN}/"
  echo "Live:  http://${DOMAIN}/live.html"
else
  echo "Site:  https://${DOMAIN}/"
  echo "Live:  https://${DOMAIN}/live.html"
fi

echo ""
echo "Streamer example:"
echo "srt://${DOMAIN}:8890?streamid=publish:game1:publisher:${PUBLISH_KEY}&pkt_size=1316"
echo ""
echo "Host example:"
echo "srt://${DOMAIN}:8890?streamid=read:game1:host:${HOST_KEY}&pkt_size=1316"
echo "======================================================================================================"