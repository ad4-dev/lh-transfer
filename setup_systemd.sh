#!/bin/bash
# systemd מוקשח לשרת — פותר crash-loop: ה-thread של הסורק non-daemon ולא מת ב-SIGTERM,
# אז ExecStartPre הורג כל מי שמחזיק 8733 לפני הפעלה, ו-KillSignal=SIGKILL שה-stop באמת יהרוג.
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/setup_systemd.sh | bash
cd /root/Lead_Hunter || { echo "אין /root/Lead_Hunter"; exit 1; }

[ -f .crm_pass ] || echo 'meWXI11PD1ju' > .crm_pass
chmod 600 .crm_pass
echo "LEADHUNTER_PASSWORD=$(cat .crm_pass)" > .crm_env
chmod 600 .crm_env

echo "== עוצר הכל ביסודיות =="
systemctl stop leadhunter 2>/dev/null
pkill -9 -f 'server\.py' 2>/dev/null
for pid in $(ss -ltnp 2>/dev/null | grep ':8733 ' | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do kill -9 "$pid" 2>/dev/null; done
for i in $(seq 1 20); do ss -ltn 2>/dev/null | grep -q ':8733 ' || break; sleep 1; done

cat > /etc/systemd/system/leadhunter.service <<'UNIT'
[Unit]
Description=Lead Hunter CRM dashboard + scanner
After=network.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
WorkingDirectory=/root/Lead_Hunter
EnvironmentFile=/root/Lead_Hunter/.crm_env
# הורג כל שריד שמחזיק את 8733 לפני כל הפעלה (ה-thread non-daemon לא מת ב-SIGTERM)
ExecStartPre=/bin/bash -c 'for pid in $(ss -ltnp 2>/dev/null | grep ":8733 " | grep -oE "pid=[0-9]+" | cut -d= -f2 | sort -u); do kill -9 "$pid"; done; sleep 2; exit 0'
ExecStart=/root/Lead_Hunter/venv/bin/python server.py --anytime
Restart=always
RestartSec=10
KillSignal=SIGKILL
TimeoutStopSec=8

[Install]
WantedBy=multi-user.target
UNIT

echo "== מפעיל =="
systemctl daemon-reload
systemctl reset-failed leadhunter 2>/dev/null
systemctl enable leadhunter >/dev/null 2>&1 && echo "✓ יופעל אוטומטית באתחול"
systemctl restart leadhunter
code=000
for i in $(seq 1 15); do sleep 2; code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8733/ 2>/dev/null); { [ "$code" = "401" ] || [ "$code" = "200" ]; } && break; done
echo "-----------------------------------"
echo "active:  $(systemctl is-active leadhunter)"
echo "NRestarts: $(systemctl show leadhunter -p NRestarts --value)"
echo "local dashboard: HTTP $code (200/401=תקין)"
if [ "$code" != "401" ] && [ "$code" != "200" ]; then echo "── journal ──"; journalctl -u leadhunter -n 15 --no-pager; fi
echo "=== SYSTEMD READY (SIGKILL + kill-on-start) ==="
