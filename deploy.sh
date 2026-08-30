#!/bin/bash
# פריסה ל-VPS: משיכת bundle + הפעלה מחדש עמידה (עוצר, הורג כל מה שעל 8733, מפעיל).
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/deploy.sh | bash
echo "== מושך bundle =="
cd /root/lh-transfer && git pull -q && echo "✓ bundle עודכן"
cd /root/Lead_Hunter || { echo "אין /root/Lead_Hunter"; exit 1; }

git stash -q 2>/dev/null || true
if [ -e sheets_push.py ] && ! git ls-files --error-unmatch sheets_push.py >/dev/null 2>&1; then
  mkdir -p /root/_vps_bak; mv sheets_push.py /root/_vps_bak/ && echo "↩ גובה sheets_push.py הישן"
fi
if git pull -q; then echo "✓ קוד עודכן ל: $(git log --oneline -1)"; else echo "✗ git pull נכשל:"; git pull 2>&1 | tail -5; fi

# --- פונקציית ניקוי פורט: הורג כל תהליך שמחזיק את 8733 וממתין לשחרור ---
free_port() {
  pkill -9 -f 'server.py' 2>/dev/null
  for pid in $(ss -ltnp 2>/dev/null | awk -F'pid=' '/:8733 /{print $2}' | grep -oE '^[0-9]+' | sort -u); do
    echo "  הורג תהליך זר $pid על 8733"; kill -9 "$pid" 2>/dev/null
  done
  for i in $(seq 1 20); do ss -ltn 2>/dev/null | grep -q ':8733 ' || break; sleep 1; done
}

echo "== מפעיל מחדש =="
if systemctl list-unit-files 2>/dev/null | grep -q '^leadhunter.service'; then
  echo "LEADHUNTER_PASSWORD=$(cat .crm_pass 2>/dev/null || echo meWXI11PD1ju)" > .crm_env; chmod 600 .crm_env
  systemctl stop leadhunter 2>/dev/null; sleep 2
  free_port                                   # הורג שרתי nohup זרים שנשארו מלפני systemd
  systemctl reset-failed leadhunter 2>/dev/null   # מאפס מונה crash-loop
  systemctl start leadhunter && echo "✓ הופעל מחדש דרך systemd"
else
  free_port
  [ -f .crm_pass ] || echo 'meWXI11PD1ju' > .crm_pass; chmod 600 .crm_pass
  LEADHUNTER_PASSWORD="$(cat .crm_pass)" nohup venv/bin/python server.py --anytime > /root/server.log 2>&1 &
fi
code=000
for i in $(seq 1 12); do sleep 2; code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8733/ 2>/dev/null); { [ "$code" = "401" ] || [ "$code" = "200" ]; } && break; done
echo "local dashboard: HTTP $code (200/401=תקין)"
if [ "$code" != "401" ] && [ "$code" != "200" ]; then echo "--- לוג (סוף) ---"; journalctl -u leadhunter -n 15 --no-pager 2>/dev/null || tail -15 /root/server.log; fi
echo === DEPLOYED ===
