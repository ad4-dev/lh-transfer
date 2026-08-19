#!/bin/bash
# run_forever.sh — מפעיל את הצייד 24/7 על ה-VPS: מנת סריקה -> דחיפה לגיליון -> הפוגה.
# עוצר לולאות קודמות כדי לא להריץ שתיים במקביל. מריצים:
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/run_forever.sh | bash
cd /root/Lead_Hunter

echo "עוצר לולאות/סריקות קודמות..."
pkill -f "server.py --once backfill" 2>/dev/null || true
pkill -f "sheets_push.py" 2>/dev/null || true
sleep 3

echo "מפעיל לולאה משולבת ברקע (סריקה + דחיפה לגיליון, מנותק מהקונסול)..."
nohup bash -c '
while true; do
    venv/bin/python server.py --once backfill || sleep 2400
    venv/bin/python sheets_push.py || true
    sleep 120
done
' > /root/run.log 2>&1 &

sleep 1
echo "=== RUNNING pid $! — הלוג: /root/run.log ==="
