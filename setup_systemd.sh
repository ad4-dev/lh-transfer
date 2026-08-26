#!/bin/bash
# התקנת systemd לשרת הדשבורד — פותר את מרוץ הפורט לצמיתות + שורד reboot.
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/setup_systemd.sh | bash
cd /root/Lead_Hunter || { echo "אין /root/Lead_Hunter"; exit 1; }

# קובץ סביבה עם הסיסמה (systemd קורא ממנו, לא מהפקודה)
[ -f .crm_pass ] || echo 'meWXI11PD1ju' > .crm_pass
chmod 600 .crm_pass
echo "LEADHUNTER_PASSWORD=$(cat .crm_pass)" > .crm_env
chmod 600 .crm_env

# עצור כל שרת nohup ישן שמחזיק את הפורט (systemd ישתלט)
echo "== עוצר שרתים ישנים =="
pkill -9 -f 'server.py' 2>/dev/null
for pid in $(ss -ltnp 2>/dev/null | awk -F'pid=' '/:8733 /{print $2}' | grep -oE '^[0-9]+' | sort -u); do kill -9 "$pid" 2>/dev/null; done
for i in $(seq 1 20); do ss -ltn 2>/dev/null | grep -q ':8733 ' || break; sleep 1; done

# צור את יחידת ה-systemd
cat > /etc/systemd/system/leadhunter.service <<'UNIT'
[Unit]
Description=Lead Hunter CRM dashboard + scanner
After=network.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=/root/Lead_Hunter
EnvironmentFile=/root/Lead_Hunter/.crm_env
ExecStart=/root/Lead_Hunter/venv/bin/python server.py --anytime
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

echo "== מפעיל את השירות =="
systemctl daemon-reload
systemctl enable leadhunter >/dev/null 2>&1 && echo "✓ יופעל אוטומטית באתחול"
systemctl restart leadhunter
code=000
for i in $(seq 1 12); do sleep 2; code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8733/ 2>/dev/null); [ "$code" = "401" ] && break; done
echo "-----------------------------------"
echo "active:  $(systemctl is-active leadhunter)"
echo "enabled: $(systemctl is-enabled leadhunter)"
echo "local dashboard: HTTP $code (401=תקין)"
if [ "$code" != "401" ]; then echo "--- journalctl (סוף) ---"; journalctl -u leadhunter -n 20 --no-pager; fi
echo === SYSTEMD READY ===
