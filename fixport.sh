#!/bin/bash
# אבחון + תיקון crash-loop של פורט 8733: מראה מי מחזיק, הורג הכל, מפעיל נקי.
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/fixport.sh | bash
echo "════════ אבחון ════════"
echo "── מי מאזין על 8733 (לפני) ──"
ss -ltnp 2>/dev/null | grep ':8733 ' || echo "  (ss לא מראה כלום על 8733)"
echo "── תהליכי server.py / run_forever / nohup ──"
ps -eo pid,ppid,etime,cmd 2>/dev/null | grep -E 'server\.py|run_forever|nohup' | grep -v grep || echo "  (אין)"
echo "── crontab (respawner אפשרי) ──"
crontab -l 2>/dev/null | grep -vE '^\s*#|^\s*$' || echo "  (crontab ריק)"
echo "── שירותי systemd עם 8733/server ──"
systemctl list-units --type=service 2>/dev/null | grep -iE 'leadhunter|server' || echo "  (רק leadhunter)"

echo "════════ תיקון ════════"
systemctl stop leadhunter 2>/dev/null; echo "עצר leadhunter"
systemctl reset-failed leadhunter 2>/dev/null; echo "איפס מונה קריסות"
# הרוג respawners
pkill -9 -f run_forever 2>/dev/null && echo "נהרג run_forever"
pkill -9 -f 'server\.py' 2>/dev/null && echo "נהרגו server.py"
# הרוג לפי פורט בכל שיטה
command -v fuser >/dev/null && fuser -k 8733/tcp 2>/dev/null && echo "fuser ניקה 8733"
for pid in $(ss -ltnp 2>/dev/null | grep ':8733 ' | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do
  echo "הורג PID $pid שמחזיק 8733"; kill -9 "$pid" 2>/dev/null
done
# המתן לשחרור מלא
for i in $(seq 1 30); do ss -ltn 2>/dev/null | grep -q ':8733 ' || break; sleep 1; done
if ss -ltn 2>/dev/null | grep -q ':8733 '; then
  echo "⚠ עדיין תפוס אחרי 30ש':"; ss -ltnp 2>/dev/null | grep ':8733 '
else
  echo "✓ פורט 8733 פנוי"
fi

echo "════════ הפעלה ════════"
systemctl start leadhunter
code=000
for i in $(seq 1 12); do sleep 2; code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8733/ 2>/dev/null); { [ "$code" = "401" ] || [ "$code" = "200" ]; } && break; done
echo "local dashboard: HTTP $code (200/401=תקין)"
echo "NRestarts: $(systemctl show leadhunter -p NRestarts --value)"
if [ "$code" != "401" ] && [ "$code" != "200" ]; then echo "── journal ──"; journalctl -u leadhunter -n 12 --no-pager 2>/dev/null; fi
echo "═══════ DONE ═══════"
