#!/bin/bash
set -euo pipefail

ROLE=""
RPM_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      ROLE="$2"
      shift 2
      ;;
    --rpm-dir)
      RPM_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$ROLE" ]]; then
  echo "--role is required" >&2
  exit 1
fi

case "$ROLE" in
  b1)
    HOSTNAME_VALUE="b1-paloalto"
    PAGE_TITLE="VPC-B | Palo Alto VM-Series NGFW"
    PAGE_HEADING="Palo Alto VM-Series NGFW"
    PAGE_BODY="Management landing page for the simulated Palo Alto three-ENI deployment."
    ;;
  c1_portal)
    HOSTNAME_VALUE="c1-portal"
    PAGE_TITLE="VPC-C | AppGate SDP - Portal"
    PAGE_HEADING="AppGate SDP - Portal"
    PAGE_BODY="Clientless access portal for the AppGate simulation."
    ;;
  c2_gateway)
    HOSTNAME_VALUE="c2-gateway"
    PAGE_TITLE="VPC-C | AppGate SDP - Gateway"
    PAGE_HEADING="AppGate SDP - Gateway"
    PAGE_BODY="Gateway enforcement point for the AppGate simulation."
    ;;
  c3_controller)
    HOSTNAME_VALUE="c3-controller"
    PAGE_TITLE="VPC-C | AppGate SDP - Controller"
    PAGE_HEADING="AppGate SDP - Controller"
    PAGE_BODY="Controller plane for the AppGate simulation."
    ;;
  *)
    echo "Unsupported role: $ROLE" >&2
    exit 1
    ;;
esac

sudo hostnamectl set-hostname "$HOSTNAME_VALUE"

if [[ -n "$RPM_DIR" && -d "$RPM_DIR" ]] && compgen -G "$RPM_DIR/*.rpm" >/dev/null; then
  sudo rpm -Uvh --replacepkgs --replacefiles "$RPM_DIR"/*.rpm >/dev/null
else
  sudo dnf install -y nginx psmisc >/dev/null
fi

if ! command -v openssl >/dev/null 2>&1; then
  sudo dnf install -y openssl >/dev/null
fi

sudo systemctl disable --now lab-web.service >/dev/null 2>&1 || true
sudo rm -f /etc/systemd/system/lab-web.service
sudo systemctl daemon-reload

sudo fuser -k 80/tcp 2>/dev/null || true
sudo fuser -k 443/tcp 2>/dev/null || true

sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/selfsigned.key \
  -out /etc/nginx/ssl/selfsigned.crt \
  -subj "/CN=$HOSTNAME_VALUE.lab/O=TGW-Lab/C=US" >/dev/null 2>&1

sudo tee /usr/share/nginx/html/index.html >/dev/null <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>$PAGE_TITLE</title>
  <style>
    body { font-family: "Segoe UI", sans-serif; margin: 0; background: #0f172a; color: #e2e8f0; }
    main { max-width: 720px; margin: 6rem auto; padding: 2rem; background: #111827; border: 1px solid #334155; border-radius: 18px; }
    h1 { margin-top: 0; }
    p { line-height: 1.6; }
    code { background: #1e293b; padding: 0.15rem 0.35rem; border-radius: 6px; }
  </style>
</head>
<body>
  <main>
    <h1>$PAGE_HEADING</h1>
    <p>$PAGE_BODY</p>
    <p>Role key: <code>$ROLE</code></p>
    <p>Host: <code>$HOSTNAME_VALUE</code></p>
  </main>
</body>
</html>
HTML

sudo tee /etc/nginx/conf.d/ssl.conf >/dev/null <<'NGINXCONF'
server {
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
}
NGINXCONF

sudo systemctl enable --now sshd >/dev/null 2>&1 || true
sudo systemctl enable nginx >/dev/null
sudo systemctl restart nginx

echo "Configured nginx for role $ROLE on host $HOSTNAME_VALUE"
