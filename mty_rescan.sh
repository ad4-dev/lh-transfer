#!/bin/bash
# mty_rescan.sh — סריקה מחדש של מטה יהודה, אחרי שהלידים אבדו.
#
# מריצים רק *אחרי* שהתיקון (35c115c) נפרס, אחרת אותה סריקה תאבד שוב.
# מה זה עושה: מאפס את "מה כבר נסרק" (done/pages/finished) ומחזיר את הסורק
# לשלב ההשלמה. הלידים שכבר במאגר לא נמחקים, וגם לא ההיסטוריה של הצוות —
# הסורק פשוט יעבור שוב על אותן בקשות ויכתוב אותן הפעם לדיסק.
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/mty_rescan.sh | bash
set -e
cd /root/Lead_Hunter || { echo "אין /root/Lead_Hunter"; exit 1; }

if ! grep -q "def publish" server.py || ! grep -q "לפני ש-done ייכתב" server.py; then
  echo "✗ התיקון לא נמצא בקוד שעל השרת. קודם:"
  echo "  curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/deploy.sh | bash"
  exit 1
fi

echo "== עוצר את השירות =="
systemctl stop leadhunter 2>/dev/null || true
mkdir -p /root/_vps_bak
cp mty_state.json "/root/_vps_bak/mty_state.$(date +%F_%H%M).json"
echo "✓ גיבוי: /root/_vps_bak/mty_state.$(date +%F_%H%M).json"

venv/bin/python - <<'PY'
import json
with open("mty_state.json", encoding="utf-8") as f:
    st = json.load(f)
print(f"  לפני:  שלב={st.get('phase')}  נסגרו={len(st.get('done', []))}  "
      f"סוגים שהושלמו={len(st.get('finished', []))}  "
      f"ממתינים={len(st.get('ripening', {}))}")
st["phase"] = "backfill"
st["done"] = []          # מה שסומן כסגור בלי שהליד נשמר — זה הלב של האובדן
st["pages"] = {}         # חוזרים לעמוד הראשון בכל סוג בקשה
st["finished"] = []
with open("mty_state.json", "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
print(f"  אחרי:  שלב=backfill  נסגרו=0  "
      f"ממתינים={len(st.get('ripening', {}))} (נשמרו)")
PY

echo "== מפעיל =="
systemctl start leadhunter
sleep 3
systemctl is-active leadhunter
echo "הסריקה מתחילה מחדש. ~9,400 בקשות, בערך יממה."
echo "מעקב:  journalctl -u leadhunter -f"
echo "בדיקה: curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/mty.sh | bash"
