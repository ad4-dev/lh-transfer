#!/bin/bash
# פריסה ל-VPS: משיכת ה-bundle העדכני + הפעלה מחדש. עמיד מול קבצים לא-מנוהלים.
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/deploy.sh | bash
echo "== מושך bundle =="
cd /root/lh-transfer && git pull -q && echo "✓ bundle עודכן"
cd /root/Lead_Hunter || { echo "אין /root/Lead_Hunter"; exit 1; }

# שינוי מקומי מנוהל (כגון כוונון sed) — לגיבוי בלבד, לא לדרוס את הקוד החדש
git stash -q 2>/dev/null || true

# קובץ לא-מנוהל שחוסם את המשיכה — לגבות ולפנות כדי שהגרסה המנוהלת תיכנס
if [ -e sheets_push.py ] && ! git ls-files --error-unmatch sheets_push.py >/dev/null 2>&1; then
  mkdir -p /root/_vps_bak; mv sheets_push.py /root/_vps_bak/ && echo "↩ גובה sheets_push.py הישן"
fi

if git pull -q; then
  echo "✓ קוד עודכן ל: $(git log --oneline -1)"
else
  echo "✗ git pull נכשל:"; git pull 2>&1 | tail -5
fi

echo "== מפעיל מחדש =="
pkill -9 -f server.py 2>/dev/null; sleep 5
[ -f .crm_pass ] || echo 'meWXI11PD1ju' > .crm_pass
chmod 600 .crm_pass
LEADHUNTER_PASSWORD="$(cat .crm_pass)" nohup venv/bin/python server.py --anytime > /root/server.log 2>&1 &
code=000
for i in $(seq 1 12); do
  sleep 2
  code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8733/ 2>/dev/null)
  [ "$code" = "401" ] && break
done
echo "local dashboard: HTTP $code (401=תקין)"
if [ "$code" != "401" ]; then echo "--- server.log (סוף) ---"; tail -20 /root/server.log; fi
pgrep -af server.py | head -2
echo === DEPLOYED ===
