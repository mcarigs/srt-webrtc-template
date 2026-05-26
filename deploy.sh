#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================================================================================"
echo "                      Zero-Latency SRT / WebRTC Restream Service — Deploy"
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
EOF
}

validate_domain() {
  if [[ -z "${DOMAIN:-}" ]]; then
    echo "❌ DOMAIN is not set."
    exit 1
  fi
  if [[ "$DOMAIN" =~ ^[0-9.]+$ ]]; then
    echo "⚠️ Notice: IP Address detected instead of a domain name."
    echo "   Let's Encrypt cannot issue certificates for IP addresses."
    echo "   The server will be configured in HTTP-only mode."
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
    echo "A domain name or IP Address is required."
    read -r -p "Enter your domain or IP (e.g. stream.example.com or 192.168.1.50): " DOMAIN
  fi
  validate_domain
  save_env
  echo "✅ Using address: $DOMAIN"
}

render_configs() {
  mkdir -p generated
  
  if [ "$USE_HTTP" = true ]; then
    cat > generated/default.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }

    location /live.html {
        auth_basic "VIP Commentator Access";
        auth_basic_user_file /etc/nginx/.htpasswd;
        root /usr/share/nginx/html;
    }
}
EOF
    
    sed "s/__DOMAIN__/${DOMAIN}/g" mediamtx.yml > generated/mediamtx.yml
    sed -i "s/webrtcEncryption: true/webrtcEncryption: false/g" generated/mediamtx.yml
    sed -i "s/apiEncryption: true/apiEncryption: false/g" generated/mediamtx.yml
    echo "✅ Generated HTTP-only nginx and MediaMTX configs"
  else
    sed "s/__DOMAIN__/${DOMAIN}/g" default.conf.template > generated/default.conf
    sed "s/__DOMAIN__/${DOMAIN}/g" mediamtx.yml > generated/mediamtx.yml
    echo "✅ Generated HTTPS nginx and MediaMTX configs"
  fi
}

if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
  echo "🐳 DOCKER SETUP: Docker or Docker Compose is missing!"
  echo "Installing Docker environment..."
  sudo apt-get update
  sudo apt-get install -y docker.io docker-compose
  sudo systemctl enable docker
  sudo systemctl start docker
  echo "✅ Docker installed successfully!"
else
  echo "✅ Docker and Docker Compose are already installed."
fi

load_env
prompt_domain
render_configs

CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"

if [ "$USE_HTTP" = false ]; then
  if [[ ! -d "$CERT_DIR" ]]; then
    echo ""
    echo "🔒 SSL SETUP: No certificates found for ${DOMAIN}!"
    echo "Installing Certbot and generating new certificates..."
    sudo apt-get update && sudo apt-get install -y certbot

    docker-compose down 2>/dev/null || true

    read -r -p "Enter your email address for Let's Encrypt registration: " ssl_email
    if [[ -z "$ssl_email" ]]; then
      echo "❌ Email is required for certificate registration."
      exit 1
    fi

    sudo certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "$ssl_email"
    echo "✅ SSL certificates generated for ${DOMAIN}"
  else
    echo ""
    echo "✅ SSL certificates already exist at ${CERT_DIR}"
  fi
else
  echo ""
  echo "🌐 Running in HTTP-only mode. Skipping SSL certificates."
fi

if ! command -v htpasswd &> /dev/null; then
  echo "⚙️ Installing apache2-utils for VIP security..."
  sudo apt-get update && sudo apt-get install -y apache2-utils
fi

if [[ ! -f .htpasswd ]]; then
  echo ""
  echo "🛡️ VIP ROOM SECURITY SETUP"
  read -r -p "Enter a username for the live room [default: admin]: " input_user
  VIP_USER=${input_user:-admin}
  echo "Enter the password for user: $VIP_USER"
  htpasswd -c .htpasswd "$VIP_USER"
  echo "✅ Password file created."
else
  echo "✅ Password file (.htpasswd) already exists."
fi

echo ""
echo "🚀 Starting Docker containers..."
docker-compose down 2>/dev/null || true
docker-compose up -d --force-recreate

echo ""
echo "🎉 Deployment complete!"
if [ "$USE_HTTP" = true ]; then
  echo "   Site:  http://${DOMAIN}/"
  echo "   Live:  http://${DOMAIN}/live.html"
else
  echo "   Site:  https://${DOMAIN}/"
  echo "   Live:  https://${DOMAIN}/live.html"
fi
echo "   SRT:   srt://${DOMAIN}:8890?streamid=publish:game1"
echo "======================================================================================================"
