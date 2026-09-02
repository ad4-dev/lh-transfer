#!/bin/bash
# check.sh — אבחון חיבור לשני הפורטלים מה-VPS.
# פלט באנגלית בלבד: הקונסולה של Kamatera לא מציגה עברית.
#   cd /root/lh-transfer && git pull && bash check.sh
cd /root/Lead_Hunter 2>/dev/null || { echo "no /root/Lead_Hunter"; exit 1; }
PY=venv/bin/python

MTY="https://mty.bartech-net.co.il/SearchPermitApplicationResults/?searchType=ByDetails&TypeOfPermit=51&page=1"
BS="https://handasi.complot.co.il/magicscripts/mgrqispi.dll?appname=cixpa&prgname=GetYeshuvim&siteid=93&arguments=siteid"

echo "== curl (network) =="
echo -n "  bartech: "; curl -sS -m 30 -o /dev/null -w "HTTP %{http_code}\n" "$MTY" 2>&1 | tail -1
echo -n "  complot: "; curl -sS -m 30 -o /dev/null -w "HTTP %{http_code}\n" "$BS"  2>&1 | tail -1

echo "== python (what the scanner actually does) =="
$PY - <<'EOF'
import traceback
import http_session, config
s = http_session.make_session()

def probe(name, url, params, marker):
    try:
        r = s.get(url, params=params, timeout=45)
        t = r.text
        print("  %-8s HTTP %s  len=%d  hits=%d  captcha=%s"
              % (name, r.status_code, len(t), t.count(marker),
                 ("g-recaptcha" in t) or ("nedrash" in t)))
    except Exception:
        print("  %-8s EXCEPTION:" % name)
        traceback.print_exc()

probe("bartech", config.MTY_SEARCH_URL,
      {"searchType": "ByDetails", "TypeOfPermit": "51", "page": "1"},
      "PermitApplicationDetails")

# בדיוק הבקשה שנכשלה ב-VPS (היתר 20230446), ולא בדיקת חיים גנרית:
# hits=1 פירושו שהפורטל החזיר את הבקשה, hits=0 שהוא החזיר דף שגיאה.
# הבקשה המקושרת להיתר 20230446 היא 20220643. נוכחות המספר הזה בתשובה
# היא הראיה שהפורטל החזיר נתונים אמיתיים ולא דף שגיאה.
probe("complot", config.XPA_BASE + "GetBakashotByHeter",
      {"siteId": "93", "grp": "0", "t": "0", "b": "20230446", "l": "false",
       "arguments": "siteId,grp,t,b,l"}, "20220643")
EOF

echo "== scanner state =="
$PY - <<'EOF'
import json, os, time
for name, f in (("MTY", "mty_state.json"), ("BS", "server_state.json")):
    if not os.path.exists(f):
        print("  %-4s no state file" % name); continue
    d = json.load(open(f, encoding="utf-8"))
    age = (time.time() - os.path.getmtime(f)) / 3600.0
    print("  %-4s phase=%s blocks=%s processed=%s  (written %.1fh ago)"
          % (name, d.get("phase"), d.get("block_count"),
             d.get("processed_total"), age))
EOF
echo "== END =="
