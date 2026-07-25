#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.telegram-ipa.env"
IPA="${1:-$ROOT/PersonalToolbox.ipa}"
if [[ ! -f "$IPA" ]]; then
  echo "IPA not found: $IPA" >&2
  exit 1
fi
CAPTION="${2:-PersonalToolbox IPA}"
# Telegram bot upload limit 50MB for sendDocument
SIZE=$(stat -c%s "$IPA")
if (( SIZE > 49000000 )); then
  echo "IPA too large for Telegram bot ($SIZE bytes)" >&2
  exit 1
fi
curl -fsSL -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
  -F "chat_id=${TELEGRAM_CHAT_ID}" \
  -F "caption=${CAPTION}" \
  -F "document=@${IPA};filename=PersonalToolbox.ipa" \
  -o /tmp/telegram-send-ipa.json
python3 - <<'PY'
import json
from pathlib import Path
d=json.loads(Path('/tmp/telegram-send-ipa.json').read_text())
if not d.get('ok'):
    raise SystemExit(f"Telegram send failed: {d}")
print("Telegram OK:", d.get('result',{}).get('document',{}).get('file_name'))
PY
