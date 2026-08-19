#!/bin/bash
# setup_vps.sh — התקנת הצייד על VPS ישראלי (Ubuntu). מריצים פעם אחת:
#   curl -sL https://raw.githubusercontent.com/ad4-dev/lh-transfer/main/setup_vps.sh | bash
set -e

echo "=== [1/4] מתקין תלויות מערכת (git, python, OCR עברית) ==="
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    git python3 python3-pip python3-venv tesseract-ocr tesseract-ocr-heb

echo "=== [2/4] מוריד את הקוד מ-GitHub ==="
cd /root
rm -rf lh-transfer Lead_Hunter
git clone -q https://github.com/ad4-dev/lh-transfer.git
git clone -q -b main lh-transfer/lead_hunter.bundle Lead_Hunter
cd Lead_Hunter

echo "=== [3/4] סביבת Python + תלויות (~דקה) ==="
python3 -m venv venv
venv/bin/pip install -q --upgrade pip
venv/bin/pip install -q -r requirements.txt \
    gspread google-auth google-auth-oauthlib truststore

echo "=== [4/4] בדיקות ==="
venv/bin/python -c "import socket; socket.create_connection(('handasi.complot.co.il',443),15); print('  פורטל: נגיש')"
venv/bin/python -c "import pytesseract; print('  OCR:', [l for l in pytesseract.get_languages() if l in ('heb','eng')])"

echo ""
echo "=== SETUP_DONE ==="
