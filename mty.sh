#!/bin/bash
# mty.sh — לאן נעלמו הלידים של מטה יהודה. קריאה בלבד, לא משנה כלום.
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/mty.sh | bash
cd /root/Lead_Hunter || { echo "אין /root/Lead_Hunter"; exit 1; }

echo "== קבצים (מתי נכתבו לאחרונה) =="
ls -l --time-style="+%d/%m %H:%M" leads_store.json leads.json mty_state.json 2>/dev/null \
  | awk '{printf "  %-22s %8s  %s %s\n", $NF, $5, $6, $7}'

venv/bin/python - <<'PY'
import json, collections, os

def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"  [{path}] לא נקרא: {e}")
        return None

store = load("leads_store.json") or {}
leads = store.get("leads", store)
rows = list(leads.values()) if isinstance(leads, dict) else list(leads)

print("\n== המאגר לפי ועדה ==")
per = collections.Counter()
for r in rows:
    src = r.get("source") or "bs"
    per[(src, "פעיל" if not r.get("disqualify_reason") else "ירד")] += 1
for (src, st), n in sorted(per.items()):
    print(f"  {src:<4} {st:<5} {n}")

mty = [r for r in rows if (r.get("source") or "bs") == "mty"]
gone = [r for r in mty if r.get("disqualify_reason")]
print(f"\n== מטה יהודה: {len(mty)} במאגר, {len(gone)} ירדו מהרשימה ==")
for reason, n in collections.Counter(
        (r.get("disqualify_reason") or "")[:45] for r in gone).most_common():
    print(f"  {n:>4}  {reason}")
if gone:
    print("  מתי ירדו:")
    for day, n in sorted(collections.Counter(
            (r.get("retired_at") or "לא מסומן")[:10] for r in gone).items()):
        print(f"    {day}  {n}")

# מה הדשבורד באמת מקבל
export = load("leads.json")
if isinstance(export, list):
    ex = collections.Counter((r.get("source") or "bs") for r in export)
    print(f"\n== leads.json (מה שהדשבורד מציג): {len(export)} ==")
    for src, n in sorted(ex.items()):
        print(f"  {src:<4} {n}")

st = load("mty_state.json") or {}
print("\n== מצב הסורק של מטה יהודה ==")
print(f"  שלב: {st.get('phase')}   עובדו: {st.get('processed_total')}   "
      f"חסימות ברצף: {st.get('block_count')}")
print(f"  נסגרו (done): {len(st.get('done', []))}   "
      f"ממתינים להבשלה: {len(st.get('ripening', {}))}")
PY

echo "== 5 שורות ההסרה האחרונות בלוג =="
journalctl -u leadhunter --no-pager 2>/dev/null | grep "הוסר" | tail -5
echo "  (סה\"כ הסרות בלוג: $(journalctl -u leadhunter --no-pager 2>/dev/null | grep -c "הוסר"))"
