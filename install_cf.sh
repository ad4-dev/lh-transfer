#!/bin/bash
# install_cf.sh — מתקין cloudflared על ה-VPS דרך המאגר הרשמי של Cloudflare.
# הרצה:  curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/install_cf.sh | bash
set -e
echo "=== מתקין cloudflared (מאגר רשמי) ==="
mkdir -p /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' > /etc/apt/sources.list.d/cloudflared.list
apt-get update -qq
apt-get install -y -qq cloudflared
echo ""
cloudflared --version
echo ""
echo "=== CF_INSTALLED ==="
echo "השלב הבא (הקלידי):  cloudflared tunnel login"
