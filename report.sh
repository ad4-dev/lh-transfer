#!/bin/bash
# דוח מצב הצייד: רץ? כמה עובד? כמה לידים? כמה חסימות היום?
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/report.sh | bash
cd /root/Lead_Hunter || { echo "אין /root/Lead_Hunter"; exit 1; }
echo "════════ מצב הצייד ════════"
echo "שירות: $(systemctl is-active leadhunter) · אתחול-אוטו: $(systemctl is-enabled leadhunter)"
echo "רץ מאז: $(systemctl show leadhunter -p ActiveEnterTimestamp --value)"
echo
echo "──── סורק (/status) ────"
PASS=$(cat .crm_pass 2>/dev/null)
curl -s -u "x:$PASS" http://127.0.0.1:8733/status 2>/dev/null | venv/bin/python -c '
import sys, json
try: d=json.load(sys.stdin)
except Exception: print("  (לא הצלחתי לקרוא status — אולי השרת עולה כרגע)"); sys.exit()
print("  סורק כרגע:", "כן" if d.get("scanning") else "לא")
print("  שלב:", d.get("phase"))
print("  היתרים שעובדו (מצטבר):", d.get("processed_total"))
print("  נותרו בתור:", d.get("remaining"))
print("  לידים: סהכ %s · פעילים %s · פסולים %s" % (d.get("total"), d.get("active"), d.get("retired")))
print("  סריקה אחרונה:", d.get("last_scan"))
'
echo
echo "──── היום (מהלוג) ────"
J(){ journalctl -u leadhunter --since today --no-pager 2>/dev/null; }
echo "  לידים חדשים היום: $(J | grep -cE '✓| -> ')"
echo "  חסימות היום:      $(J | grep -c 'נחסמנו')"
echo "  מנות שהושלמו היום:"
J | grep 'מנה הושלמה' | tail -3 | sed 's/^/    /'
[ -z "$(J | grep 'מנה הושלמה')" ] && echo "    (אף מנה לא הושלמה היום)"
echo
echo "──── 12 שורות אחרונות בלוג ────"
journalctl -u leadhunter -n 12 --no-pager 2>/dev/null
echo "═══════════════════════════"
