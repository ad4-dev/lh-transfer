#!/bin/bash
# סיכום לילה: כמה רץ, כמה לידים, באילו שעות נחסם, ואם היו קריסות.
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/night.sh | bash
cd /root/Lead_Hunter || { echo "אין /root/Lead_Hunter"; exit 1; }
SINCE=$(date -d 'yesterday 21:00' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'yesterday')
UNTIL=$(date -d 'today 09:00'     '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'now')
CLEAN() { sed -E 's/ leadhunter-il [a-z]+\[[0-9]+\]://'; }
N() { journalctl -u leadhunter --since "$SINCE" --until "$UNTIL" --no-pager 2>/dev/null; }

echo "════════ סיכום לילה ════════"
echo "חלון: $SINCE  →  $UNTIL"
echo
echo "── מצב השירות ──"
echo "פעיל: $(systemctl is-active leadhunter) · אתחולים אוטומטיים (NRestarts): $(systemctl show leadhunter -p NRestarts --value)"
echo "רץ מאז: $(systemctl show leadhunter -p ActiveEnterTimestamp --value)"
echo
echo "── ספירות הלילה ──"
echo "  שורות לוג:            $(N | wc -l)"
echo "  לידים חדשים:          $(N | grep -cE '✓| -> ')"
echo "  חסימות (נחסמנו):      $(N | grep -c 'נחסמנו')"
echo "  קריסות פורט (8733):   $(N | grep -c 'Address already in use')"
echo
echo "── שעות החסימות ──"
if [ -n "$(N | grep 'נחסמנו')" ]; then N | grep 'נחסמנו' | CLEAN | sed 's/^/  /' | head -40
else echo "  (אין חסימות בחלון)"; fi
echo
echo "── לידים חדשים בלילה (זמן + כתובת) ──"
if [ -n "$(N | grep -E '✓| -> ')" ]; then N | grep -E '✓| -> ' | CLEAN | sed 's/^/  /' | head -40
else echo "  (לא נמצאו לידים חדשים בחלון)"; fi
echo
echo "── מנות שהושלמו ──"
if [ -n "$(N | grep 'מנה הושלמה')" ]; then N | grep 'מנה הושלמה' | CLEAN | sed 's/^/  /' | tail -12
else echo "  (אף מנה לא הושלמה בחלון)"; fi
echo
echo "── סה\"כ נוכחי (/status) ──"
curl -s -u "x:$(cat .crm_pass 2>/dev/null)" http://127.0.0.1:8733/status 2>/dev/null | venv/bin/python -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: print("  (status לא זמין — ייתכן שהשרת לא עולה)"); sys.exit()
print("  לידים: סהכ %s · פעילים %s · פסולים %s"%(d.get("total"),d.get("active"),d.get("retired")))
print("  שלב: %s · היתרים שעובדו (מצטבר): %s"%(d.get("phase"),d.get("processed_total")))
'
echo "════════════════════════════"
