# -*- coding: utf-8 -*-
"""
sheets_push.py — דוחף את כל הלידים מ-leads_store.json לגיליון Google לפי ID.

מתחבר ב-OAuth (בתור המשתמש) — לא Service Account, כי הארגון חוסם מפתחות SA.
truststore גורם ל-Python לסמוך על תעודות ה-Windows (כולל נטפרי), אחרת ה-SSL
מול Google נכשל כמו שקרה עם git.

הרצה ראשונה פותחת דפדפן לאישור; אחרי זה הטוקן נשמר וזה רץ לבד.
"""
import truststore
truststore.inject_into_ssl()

import json
import os
import gspread
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request

SHEET_ID = "1EFNsjBjL7UIY75CHsVV6P4nkeu_V-sDlLXehZyoFP8Q"
STORE = "leads_store.json"
SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]
TOKEN = "authorized_user.json"


def get_creds():
    """OAuth בתור המשתמש. הרצה ראשונה מדפיסה קישור (בלי לפתוח דפדפן),
    כדי שאפשר לפתוח אותו בדפדפן הנכון. אחר כך הטוקן נשמר ומתחדש לבד."""
    if os.path.exists(TOKEN):
        creds = Credentials.from_authorized_user_file(TOKEN, SCOPES)
        if creds and creds.valid:
            return creds
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
            open(TOKEN, "w").write(creds.to_json())
            return creds
    flow = InstalledAppFlow.from_client_secrets_file("credentials.json", SCOPES)
    creds = flow.run_local_server(port=0, open_browser=False,
                                  authorization_prompt_message=
                                  "\n>>> פתחי את הקישור הבא בדפדפן המחובר ל-ad4.co.il:\n{url}\n")
    open(TOKEN, "w").write(creds.to_json())
    return creds

HEADERS = [
    "סטטוס", "שלב טיפול", "עדיפות", "רשימה", "כתובת", "שכונה",
    "הקשר לשיחה",
    "בעל ההיתר — שם", "בעל ההיתר — טלפון", "טלפון מאומת", "בעל ההיתר — מייל",
    "בעל הנכס — שם", "בעל הנכס — טלפון", "בעל הנכס — מייל",
    "עורך הבקשה — שם", "עורך הבקשה — טלפון", "עורך הבקשה — מייל",
    "מהנדס — שם", "מהנדס — טלפון", "מהנדס — מייל",
    "מהות הבקשה", 'שטח מ"ר', "תאריך היתר", "ותק (שנים)",
    "גוש", "חלקה", "תיק בניין", "מספר בקשה",
    "דורש אימות ידני", "סיבת פסילה", "קישור להיתר", "קישור לתיק",
]


def c(lead, role, field):
    o = lead.get(role) or {}
    return (o.get(field) or "") if isinstance(o, dict) else ""


def context(L):
    """הקשר לשיחה — נגזר מנתוני ההיתר בלבד (בלי מקורות חיצוניים):
    פרטי/חברה, היקף הפרויקט, וסוג העבודה."""
    who = "חברה/קבלן" if L.get("is_company") else "פרטי"
    try:
        s = float(L.get("sqm") or 0)
    except (TypeError, ValueError):
        s = 0
    scale = ("פרויקט גדול" if s >= 500 else "בינוני" if s >= 150
             else "קטן/תוספת" if s > 0 else "")
    parts = [who]
    if scale:
        parts.append(scale)
    if s:
        parts.append(f'{s:g} מ"ר')
    if L.get("mahut"):
        parts.append(L["mahut"])
    return " · ".join(parts)


def row(L):
    return [
        "נפסל" if L.get("disqualify_reason") else "ליד פעיל",
        L.get("handling_status", ""), L.get("priority", ""), L.get("list_name", ""),
        L.get("full_address", ""), L.get("neighborhood", ""),
        context(L),
        c(L, "permit_holder", "name"), c(L, "permit_holder", "phone"),
        "✓" if c(L, "permit_holder", "phone_verified") else "", c(L, "permit_holder", "email"),
        c(L, "property_owner", "name"), c(L, "property_owner", "phone"), c(L, "property_owner", "email"),
        c(L, "request_editor", "name"), c(L, "request_editor", "phone"), c(L, "request_editor", "email"),
        c(L, "structure_engineer", "name"), c(L, "structure_engineer", "phone"), c(L, "structure_engineer", "email"),
        L.get("mahut", ""), L.get("sqm", ""), L.get("permit_date", ""), L.get("seniority_years", ""),
        L.get("gush", ""), L.get("helka", ""), L.get("building_file", ""), L.get("request_number", ""),
        "כן" if L.get("needs_manual_verify") else "", L.get("disqualify_reason", ""),
        L.get("pdf_link", ""), L.get("case_link", ""),
    ]


def push():
    store = json.load(open(STORE, encoding="utf-8"))
    leads = store.get("leads", store)
    rows = sorted(leads.values(),
                  key=lambda L: (1 if L.get("disqualify_reason") else 0,
                                 L.get("priority_rank") or 9))
    gc = gspread.authorize(get_creds())
    sh = gc.open_by_key(SHEET_ID)
    ws = sh.sheet1
    data = [HEADERS] + [[str(x) for x in row(L)] for L in rows]
    ws.clear()
    ws.update(range_name="A1", values=data)
    ws.freeze(rows=1)
    print(f"נדחפו {len(rows)} לידים לגיליון")


if __name__ == "__main__":
    push()
