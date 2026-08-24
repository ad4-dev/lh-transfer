#!/bin/bash
# status.sh — בדיקת מצב הצייד על ה-VPS. הרצה:
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/status.sh | bash
cd /root/Lead_Hunter

echo "=== [1] האם server.py רץ? ==="
pgrep -af "server.py" | head -3 || echo "  ⚠ לא רץ!"

echo ""
echo "=== [2] מאגר הלידים ==="
venv/bin/python -c "
import json
d=json.load(open('leads_store.json',encoding='utf-8')); leads=d.get('leads',d)
fs=[L.get('first_seen','') for L in leads.values() if L.get('first_seen')]
lc=[L.get('last_checked','') for L in leads.values() if L.get('last_checked')]
print('  סהכ לידים:', len(leads))
print('  פעילים:', sum(1 for L in leads.values() if not L.get('disqualify_reason')))
print('  ליד אחרון שנוסף (first_seen):', max(fs) if fs else '?')
print('  בדיקה אחרונה (last_checked):', max(lc) if lc else '?')
print('  סריקה אחרונה (meta.last_scan):', d.get('meta',{}).get('last_scan','?'))
"

echo ""
echo "=== [3] שלב הסריקה + חסימות ==="
cat server_state.json 2>/dev/null
echo "  חסימות בלוג:"; grep -c -iE "Blocked|429" /root/server.log 2>/dev/null || echo "  0"

echo ""
echo "=== [4] 30 שורות אחרונות מהלוג ==="
tail -30 /root/server.log 2>/dev/null || echo "  אין לוג"
echo ""
echo "=== END ==="
