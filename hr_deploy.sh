#!/usr/bin/env bash
# Update an already-installed HR system on the VPS.
#
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/hr_deploy.sh | bash
#
# Right after a push the raw /main/ URL is CDN-stale for a minute or two. Pin the
# same commit for both the script and the bundle to bypass it:
#   BASE=https://raw.githubusercontent.com/ad4-dev/lh-transfer/<SHA>
#   curl -sL $BASE/hr_deploy.sh | HR_RAW_BASE=$BASE bash
#
# The database in instance/ is never touched.
set -euo pipefail

APP_DIR=/root/HR
BUNDLE_DIR=/root/hr-transfer
BUNDLE=$BUNDLE_DIR/hr.bundle
RAW=${HR_RAW_BASE:-https://raw.githubusercontent.com/ad4-dev/lh-transfer/main}
PORT=8080

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

[ -d "$APP_DIR/.git" ] || {
  echo "No install at $APP_DIR. Run hr_setup.sh first." >&2
  exit 1
}

say "Fetching the bundle"
mkdir -p "$BUNDLE_DIR"
curl -fsSL "$RAW/hr.bundle" -o "$BUNDLE.new"
git bundle verify "$BUNDLE.new" >/dev/null
mv "$BUNDLE.new" "$BUNDLE"

BEFORE=$(git -C "$APP_DIR" rev-parse HEAD)

say "Updating the working tree"
# Any hand-edit made on the VPS is stashed rather than silently overwritten.
if ! git -C "$APP_DIR" diff --quiet; then
  warn "local changes found in $APP_DIR - stashing them"
  git -C "$APP_DIR" stash push -m "pre-deploy $(date -Iseconds)"
fi
git -C "$APP_DIR" pull "$BUNDLE" main

AFTER=$(git -C "$APP_DIR" rev-parse HEAD)
if [ "$BEFORE" = "$AFTER" ]; then
  echo "    already up to date ($AFTER)"
else
  echo "    $BEFORE -> $AFTER"
fi

say "Dependencies"
"$APP_DIR/.venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"

say "Restarting the service"
# systemd stops the old process before starting the new one, so the port is
# always free - this is what fixed the recurring "Address already in use".
systemctl restart hr.service
sleep 2

if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/login"; then
  say "OK - https://hr.ad4.co.il is serving $(git -C "$APP_DIR" rev-parse --short HEAD)"
else
  warn "the app is not answering on :$PORT"
  journalctl -u hr -n 30 --no-pager
  exit 1
fi
