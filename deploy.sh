#!/bin/bash
# פריסה ל-VPS: משיכת ה-bundle העדכני מ-lh-transfer + הפעלה מחדש של השרת.
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/deploy.sh | bash
echo "== מושך את ה-bundle העדכני =="
cd /root/lh-transfer && git pull -q && echo "✓ bundle עודכן"
cd /root/Lead_Hunter || { echo "אין /root/Lead_Hunter"; exit 1; }
git stash -q 2>/dev/null || true          # לשמר שינוי מקומי (sed) כגיבוי, לא לדרוס
if git pull -q; then echo "✓ קוד עודכן ל: $(git log --oneline -1)"; else echo "✗ git pull נכשל"; fi
echo "== מפעיל מחדש את השרת =="
pkill -9 -f server.py 2>/dev/null; sleep 4
[ -f .crm_pass ] || echo 'meWXI11PD1ju' > .crm_pass
chmod 600 .crm_pass
LEADHUNTER_PASSWORD="$(cat .crm_pass)" nohup venv/bin/python server.py --anytime > /root/server.log 2>&1 &
sleep 7
curl -s -o /dev/null -w "local dashboard: HTTP %{http_code} (401=תקין)\n" http://127.0.0.1:8733/
pgrep -af server.py | head -2
echo === DEPLOYED ===
