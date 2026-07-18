#!/usr/bin/env bash
# Configure Share Extension signing for CI, or strip embed if no share profile secret.
set -euo pipefail

PBX="${GITHUB_WORKSPACE:-.}/PersonalToolbox.xcodeproj/project.pbxproj"
EXPORT="${GITHUB_WORKSPACE:-.}/ExportOptions.plist"
SHARE_PROFILE_B64="${SHARE_BUILD_PROVISION_PROFILE_BASE64:-}"
SHARE_SPECIFIER="${SHARE_PROVISION_PROFILE_SPECIFIER:-}"

if [[ -z "$SHARE_PROFILE_B64" ]]; then
  echo "No SHARE_BUILD_PROVISION_PROFILE_BASE64 — building main app only (strip Share Extension embed)."
  python3 - <<'PY'
from pathlib import Path
import re
pbx = Path("PersonalToolbox.xcodeproj/project.pbxproj")
text = pbx.read_text()
# Remove Embed Foundation Extensions from main target buildPhases lines
text2 = re.sub(
    r"\t\t\t\t[0-9A-F]{24} /\* Embed Foundation Extensions \*/,\n",
    "",
    text,
)
# Remove target dependency lines for ShareExtension
text2 = re.sub(
    r"\t\t\t\t[0-9A-F]{24} /\* PBXTargetDependency \*/,\n",
    "",
    text2,
)
# Remove ShareExtension from project targets list (keep target definition to avoid total breakage)
text2 = re.sub(
    r",\n\t\t\t\t[0-9A-F]{24} /\* ShareExtension \*/",
    "",
    text2,
)
pbx.write_text(text2)
print("Stripped Share Extension from archive graph.")
PY
  exit 0
fi

echo "Installing Share Extension provisioning profile…"
PP_PATH="${RUNNER_TEMP}/share.mobileprovision"
echo "$SHARE_PROFILE_B64" | base64 -d > "$PP_PATH"
PROFILE_UUID=$(security cms -D -i "$PP_PATH" | plutil -extract UUID raw -)
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PP_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/${PROFILE_UUID}.mobileprovision"
echo "Share profile UUID=${PROFILE_UUID}"

# Inject profile specifier into ShareExtension build settings if provided
if [[ -n "$SHARE_SPECIFIER" ]]; then
  python3 - <<PY
from pathlib import Path
import re
pbx = Path("PersonalToolbox.xcodeproj/project.pbxproj")
text = pbx.read_text()
# Add PROVISIONING_PROFILE_SPECIFIER to ShareExtension configs that have PRODUCT_BUNDLE_IDENTIFIER = app.parsnip6345.lake8262.share
spec = '''${SHARE_SPECIFIER}'''
needle = 'PRODUCT_BUNDLE_IDENTIFIER = app.parsnip6345.lake8262.share;'
insert = f'PRODUCT_BUNDLE_IDENTIFIER = app.parsnip6345.lake8262.share;\\n\\t\\t\\t\\tPROVISIONING_PROFILE_SPECIFIER = "{spec}";'
if 'PROVISIONING_PROFILE_SPECIFIER' not in text.split('lake8262.share')[1][:200]:
    text = text.replace(needle, insert)
    pbx.write_text(text)
    print("Injected SHARE_PROVISION_PROFILE_SPECIFIER")
else:
    print("Share profile specifier already present or pattern mismatch")
PY
fi

# ExportOptions: map extension bundle id
python3 - <<'PY'
from pathlib import Path
import re
export = Path("ExportOptions.plist")
text = export.read_text()
if "app.parsnip6345.lake8262.share" not in text:
    # insert after main profile entry
    text = text.replace(
        "<key>app.parsnip6345.lake8262</key>\n\t\t<string>00008150-001A088E148B401C6F01CD</string>",
        "<key>app.parsnip6345.lake8262</key>\n\t\t<string>00008150-001A088E148B401C6F01CD</string>\n\t\t<key>app.parsnip6345.lake8262.share</key>\n\t\t<string>SHARE_PROFILE_PLACEHOLDER</string>",
    )
    # use UUID file name as specifier often equals profile name - leave placeholder replaced below
    export.write_text(text)
    print("ExportOptions prepared for share id")
PY

if [[ -n "$SHARE_SPECIFIER" ]]; then
  sed -i "s/SHARE_PROFILE_PLACEHOLDER/${SHARE_SPECIFIER}/g" ExportOptions.plist || true
fi

echo "Share Extension signing ready"
