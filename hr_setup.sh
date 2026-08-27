#!/usr/bin/env bash
# One-time install of the HR system on the Kamatera VPS (leadhunter-il).
#
# Run from the Kamatera VNC console (NetFree blocks SSH from the office):
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/hr_setup.sh | bash
#
# Right after a push the raw /main/ URL is CDN-stale for a minute or two. To
# bypass it, pin the same commit for both the script and the bundle:
#   BASE=https://raw.githubusercontent.com/ad4-dev/lh-transfer/<SHA>
#   curl -sL $BASE/hr_setup.sh | HR_RAW_BASE=$BASE bash
#
# It is safe to re-run: existing pieces are left alone. It does NOT touch
# leadhunter.service, and it only appends to the Cloudflare tunnel config after
# backing it up.
set -euo pipefail

APP_DIR=/root/HR
BUNDLE_DIR=/root/hr-transfer
BUNDLE=$BUNDLE_DIR/hr.bundle
RAW=${HR_RAW_BASE:-https://raw.githubusercontent.com/ad4-dev/lh-transfer/main}
PORT=8080
HOSTNAME_FQDN=hr.ad4.co.il

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

# --------------------------------------------------------------------------- #
say "1/7  Packages"
apt-get update -qq
apt-get install -y -qq python3-venv python3-pip git curl

# --------------------------------------------------------------------------- #
say "2/7  Fetching the code bundle"
mkdir -p "$BUNDLE_DIR"
curl -fsSL "$RAW/hr.bundle" -o "$BUNDLE.new"
git bundle verify "$BUNDLE.new" >/dev/null
mv "$BUNDLE.new" "$BUNDLE"

if [ -d "$APP_DIR/.git" ]; then
  echo "    $APP_DIR already exists - pulling instead of cloning"
  git -C "$APP_DIR" pull "$BUNDLE" main
else
  git clone -b main "$BUNDLE" "$APP_DIR"
  git -C "$APP_DIR" remote set-url origin "$BUNDLE"
fi

# --------------------------------------------------------------------------- #
say "3/7  Python environment"
if [ ! -x "$APP_DIR/.venv/bin/python" ]; then
  python3 -m venv "$APP_DIR/.venv"
fi
"$APP_DIR/.venv/bin/pip" install -q --upgrade pip
"$APP_DIR/.venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"

# --------------------------------------------------------------------------- #
say "4/7  Secret key"
if [ ! -f "$APP_DIR/.hr_env" ]; then
  printf 'HR_SECRET_KEY=%s\n' "$(python3 -c 'import secrets; print(secrets.token_hex(32))')" \
    > "$APP_DIR/.hr_env"
  chmod 600 "$APP_DIR/.hr_env"
  echo "    generated $APP_DIR/.hr_env"
else
  echo "    $APP_DIR/.hr_env already exists - keeping it (rotating it logs everyone out)"
fi
mkdir -p "$APP_DIR/instance"
chmod 700 "$APP_DIR/instance"

# --------------------------------------------------------------------------- #
say "5/7  systemd unit"
install -m 644 "$APP_DIR/deploy/hr.service" /etc/systemd/system/hr.service
systemctl daemon-reload
systemctl enable hr.service
systemctl restart hr.service
sleep 2
systemctl --no-pager --lines=5 status hr.service || true

if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/login"; then
  echo "    OK - the app answers on 127.0.0.1:$PORT"
else
  warn "the app did not answer on :$PORT - check 'journalctl -u hr -n 50'"
fi

# --------------------------------------------------------------------------- #
say "6/7  Cloudflare tunnel ingress for $HOSTNAME_FQDN"
CF_CONFIG=""
for candidate in /root/.cloudflared/config.yml /root/.cloudflared/config.yaml \
                 /etc/cloudflared/config.yml /etc/cloudflared/config.yaml; do
  [ -f "$candidate" ] && CF_CONFIG="$candidate" && break
done

if [ -z "$CF_CONFIG" ]; then
  warn "no cloudflared config found. Add this ingress rule by hand, above the"
  warn "catch-all 404 rule, then restart cloudflared:"
  cat <<EOF

  - hostname: $HOSTNAME_FQDN
    service: http://localhost:$PORT

EOF
elif grep -q "$HOSTNAME_FQDN" "$CF_CONFIG"; then
  echo "    $HOSTNAME_FQDN is already in $CF_CONFIG - nothing to do"
else
  cp "$CF_CONFIG" "$CF_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
  echo "    backed up $CF_CONFIG"
  # Insert before the catch-all so crm.ad4.co.il keeps working untouched.
  python3 - "$CF_CONFIG" "$HOSTNAME_FQDN" "$PORT" <<'PY'
import re, sys

path, host, port = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
rule = f"  - hostname: {host}\n    service: http://localhost:{port}\n"

# The catch-all is the rule with no hostname, e.g. "- service: http_status:404".
match = re.search(r"^\s*-\s*service:\s*http_status:\s*404\s*$", text, re.M)
if match:
    text = text[:match.start()] + rule + text[match.start():]
else:
    text = text.rstrip("\n") + "\n" + rule
open(path, "w", encoding="utf-8").write(text)
print(f"    added the {host} rule to {path}")
PY

  if cloudflared tunnel ingress validate --config "$CF_CONFIG" 2>/dev/null; then
    echo "    ingress config validates"
  else
    warn "cloudflared could not validate the config - review $CF_CONFIG before restarting"
  fi

  TUNNEL=$(grep -E '^\s*tunnel:' "$CF_CONFIG" | head -1 | awk '{print $2}' || true)
  if [ -n "$TUNNEL" ]; then
    echo "    routing DNS for $HOSTNAME_FQDN to tunnel $TUNNEL"
    cloudflared tunnel route dns "$TUNNEL" "$HOSTNAME_FQDN" || \
      warn "DNS route failed - add a CNAME for $HOSTNAME_FQDN in the Cloudflare dashboard"
  else
    warn "could not read the tunnel name from $CF_CONFIG - add the DNS record by hand"
  fi

  systemctl restart cloudflared 2>/dev/null || warn "restart cloudflared yourself"
fi

# --------------------------------------------------------------------------- #
say "7/7  Initial staff accounts"
if [ -s "$APP_DIR/instance/hr.db" ]; then
  echo "    the database already exists - skipping the seed."
  echo "    Add people, or reset a password, from the 'עובדים' screen in the app."
else
  cd "$APP_DIR"
  HR_INSTANCE_DIR="$APP_DIR/instance" "$APP_DIR/.venv/bin/python" seed.py \
    --out "$APP_DIR/credentials.txt"
  chmod 600 "$APP_DIR/credentials.txt"
  warn "credentials.txt holds the one-time passwords. Hand them out, then:"
  warn "    shred -u $APP_DIR/credentials.txt"
fi

say "Done"
cat <<EOF
  service : systemctl status hr   |  journalctl -u hr -f
  local   : http://127.0.0.1:$PORT
  public  : https://$HOSTNAME_FQDN
  update  : curl -sL $RAW/hr_deploy.sh | bash
EOF
