#!/bin/bash
# setmail.sh — הגדרת התראות המייל של ה-CRM (השלב "ממתין לתיאום פגישה בשטח").
#
# מריצים בקונסולת ה-VNC של קמטרה, בשתי פקודות — קודם מורידים ואז מריצים,
# כדי שהסקריפט יוכל לשאול שאלות (בצינור curl|bash הקלט תפוס):
#
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/setmail.sh -o /tmp/setmail.sh
#   bash /tmp/setmail.sh
#
# מה הוא עושה: שואל שלושה ערכים, כותב אותם ל-/root/Lead_Hunter/.crm_env בלי
# לדרוס שורות קיימות, מפעיל מחדש את השירות, ומציע לשלוח מייל בדיקה — כדי
# שתקלת הזדהות תתגלה עכשיו ולא בליד הראשון שיגיע לשלב.
set -u

APP=${LH_APP:-/root/Lead_Hunter}
ENVFILE=$APP/.crm_env
RAW=https://raw.githubusercontent.com/ad4-dev/lh-transfer/main

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[V] %s\033[0m\n' "$*"; }
bad()  { printf '\033[1;31m[X] %s\033[0m\n' "$*"; }

# הקלט מגיע מהמסוף עצמו, גם אם הסקריפט הגיע מצינור. אם אין מסוף (הרצה
# אוטומטית, curl|bash) נופלים לקלט הרגיל — ואם גם הוא נגמר, עוצרים במקום
# להסתובב בלולאה על שאלה שאיש לא עונה עליה.
if (exec 3</dev/tty) 2>/dev/null; then exec 3</dev/tty; else exec 3<&0; fi
no_input() { bad "אין קלט מהמסוף. הורידי את הסקריפט והריצי אותו ישירות:"
             bad "  curl -sL $RAW/setmail.sh -o /tmp/setmail.sh && bash /tmp/setmail.sh"
             exit 1; }
ask()    { REPLY_VALUE=""; printf '%s' "$1" >&2
           IFS= read -r REPLY_VALUE <&3 || no_input; }
asksec() { REPLY_VALUE=""; printf '%s' "$1" >&2; stty -echo 2>/dev/null
           IFS= read -r REPLY_VALUE <&3 || { stty echo 2>/dev/null; no_input; }
           stty echo 2>/dev/null; printf '\n' >&2; }

# מספר הזדמנויות לתקן טעות הקלדה, ואז עצירה — לא לולאה אינסופית
tries() { ATTEMPTS=$((ATTEMPTS - 1))
          [ "$ATTEMPTS" -gt 0 ] || { bad "יותר מדי ניסיונות. שום דבר לא נשמר."; exit 1; }; }

is_email() {
  printf '%s' "$1" | grep -qE '^[^@[:space:],]+@[^@[:space:],]+\.[A-Za-z]{2,}$'
}

[ -d "$APP" ] || { bad "לא נמצאה התקנה ב-$APP"; exit 1; }

say "הגדרת התראות המייל"
echo "הכתובת השולחת היא חשבון Google, והסיסמה היא *סיסמת אפליקציה* בת 16"
echo "תווים מתוך אותו חשבון — לא סיסמת הכניסה הרגילה."
echo "אפשר לעצור בכל שלב עם Ctrl+C; שום דבר לא נכתב עד הסוף."

# --- כתובת השולח ---------------------------------------------------------- #
ATTEMPTS=4
while :; do
  ask "
כתובת המייל השולחת: "
  SMTP_USER=$(printf '%s' "$REPLY_VALUE" | tr -d '[:space:]')
  if is_email "$SMTP_USER"; then break; fi
  warn "זו לא נראית ככתובת מייל תקינה. שימי לב שהסימן @ יוצא נכון בקונסולה."
  tries
done

# --- סיסמת האפליקציה ------------------------------------------------------- #
ATTEMPTS=4
while :; do
  asksec "סיסמת האפליקציה (לא תוצג על המסך): "
  # גוגל מציגה אותה כארבע רביעיות עם רווחים — מסירים אותם
  SMTP_PASS=$(printf '%s' "$REPLY_VALUE" | tr -d '[:space:]')
  LEN=${#SMTP_PASS}
  if [ "$LEN" -eq 0 ]; then warn "לא הוזנה סיסמה."; tries; continue; fi
  if [ "$LEN" -ne 16 ]; then
    warn "התקבלו $LEN תווים; סיסמת אפליקציה של Google היא בת 16."
    ask "להמשיך בכל זאת? [y/N]: "
    case "$REPLY_VALUE" in [yY]*) ;; *) tries; continue ;; esac
  fi
  ok "נקלטו $LEN תווים, מסתיימים ב-…${SMTP_PASS: -4}"
  break
done

# --- נמענים ---------------------------------------------------------------- #
ATTEMPTS=4
while :; do
  ask "
כתובות היעד (וידר ושלום), מופרדות בפסיק: "
  ALERT_TO=$(printf '%s' "$REPLY_VALUE" | tr -d '[:space:]')
  BADADDR=""
  OLDIFS=$IFS; IFS=','
  for addr in $ALERT_TO; do is_email "$addr" || BADADDR="$addr"; done
  IFS=$OLDIFS
  if [ -n "$ALERT_TO" ] && [ -z "$BADADDR" ]; then break; fi
  warn "כתובת לא תקינה: ${BADADDR:-(ריק)}"
  tries
done

# --- כתובת הדשבורד (אופציונלי, לקישור בתוך המייל) -------------------------- #
SUGGEST=""
[ -r "$APP/current_url.txt" ] && SUGGEST=$(tr -d '[:space:]' < "$APP/current_url.txt")
ask "
כתובת הדשבורד לקישור בתוך המייל${SUGGEST:+ [ברירת מחדל: $SUGGEST]} (Enter לדילוג): "
DASH=$(printf '%s' "$REPLY_VALUE" | tr -d '[:space:]')
[ -z "$DASH" ] && DASH=$SUGGEST

# --- כתיבה לקובץ ----------------------------------------------------------- #
say "כותב ל-$ENVFILE"
[ -f "$ENVFILE" ] || warn "הקובץ לא היה קיים — נוצר עכשיו."
KEEP=$(grep -vE '^(LEADHUNTER_SMTP_USER|LEADHUNTER_SMTP_PASS|LEADHUNTER_ALERT_TO|LEADHUNTER_DASHBOARD_URL)=' \
       "$ENVFILE" 2>/dev/null || true)
TMP=$ENVFILE.new
{
  [ -n "$KEEP" ] && printf '%s\n' "$KEEP"
  printf 'LEADHUNTER_SMTP_USER=%s\n' "$SMTP_USER"
  printf 'LEADHUNTER_SMTP_PASS=%s\n' "$SMTP_PASS"
  printf 'LEADHUNTER_ALERT_TO=%s\n'  "$ALERT_TO"
  [ -n "$DASH" ] && printf 'LEADHUNTER_DASHBOARD_URL=%s\n' "$DASH"
} > "$TMP"
chmod 600 "$TMP"
mv "$TMP" "$ENVFILE"
ok "נשמר (הרשאות 600). הסיסמה לא מוצגת כאן:"
sed 's/^LEADHUNTER_SMTP_PASS=.*/LEADHUNTER_SMTP_PASS=***********/;
     s/^LEADHUNTER_PASSWORD=.*/LEADHUNTER_PASSWORD=***********/' "$ENVFILE" | sed 's/^/    /'

# --- מייל בדיקה ------------------------------------------------------------ #
say "מייל בדיקה"
echo "שליחה עכשיו תגלה מיד אם ההזדהות מול Google תקינה."
ask "לשלוח מייל בדיקה אל $ALERT_TO? [y/N]: "
case "$REPLY_VALUE" in
  [yY]*)
    LEADHUNTER_SMTP_USER="$SMTP_USER" LEADHUNTER_SMTP_PASS="$SMTP_PASS" \
    LEADHUNTER_ALERT_TO="$ALERT_TO" LH_APP_DIR="$APP" \
    "$APP/venv/bin/python" - <<'PY'
import os, sys
sys.path.insert(0, os.environ["LH_APP_DIR"])
from email.message import EmailMessage
from email.utils import formataddr, formatdate
import config, notify

msg = EmailMessage()
msg["Subject"] = "בדיקה: התראות ה-CRM מוגדרות"
msg["From"] = formataddr((config.SMTP_FROM_NAME, config.SMTP_USER))
msg["To"] = ", ".join(config.ALERT_TO)
msg["Date"] = formatdate(localtime=True)
msg.set_content(
    "זהו מייל בדיקה מהגדרת ההתראות של ה-CRM.\n"
    "אם קיבלתם אותו — ההגדרה תקינה, ומעכשיו תגיע הודעה בכל פעם\n"
    'שליד עובר לשלב "ממתין לתיאום פגישה בשטח".\n')
try:
    notify.send_now(msg)
    print("  המייל נשלח.")
except Exception as e:
    print(f"  השליחה נכשלה: {type(e).__name__}: {e}")
    raise SystemExit(1)
PY
    if [ $? -eq 0 ]; then ok "בדקי בתיבה של הנמענים (גם בספאם)."
    else bad "השליחה נכשלה — ברוב המקרים סיסמת אפליקציה שגויה. הריצי שוב את הסקריפט."
    fi
    ;;
  *) echo "  דילוג." ;;
esac

# --- הפעלה מחדש ------------------------------------------------------------ #
say "מפעיל מחדש את השירות"
if systemctl list-unit-files 2>/dev/null | grep -q '^leadhunter.service'; then
  systemctl restart leadhunter
  sleep 3
  systemctl is-active --quiet leadhunter && ok "leadhunter פעיל" || bad "leadhunter לא עלה"
  echo ""
  journalctl -u leadhunter -n 20 --no-pager | grep -E "התראת|זיהוי|Traceback" || \
    journalctl -u leadhunter -n 8 --no-pager
else
  warn "אין שירות systemd. הריצי את הפריסה הרגילה כדי להפעיל מחדש:"
  warn "  curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/deploy.sh | bash"
fi

say "סיום"
echo 'בלוג אמורה להופיע השורה: התראת "ממתין לתיאום פגישה בשטח" תישלח אל: ...'
echo "אם מופיע במקומה שההתראה מושבתת — משהו בקובץ לא נקלט, הריצי שוב."
