#!/usr/bin/env bash
# Prepare optional App Groups / StatusWidget for Ad Hoc CI profiles.
set -euo pipefail

MAIN_ENT="PersonalToolbox/PersonalToolbox.entitlements"
WIDGET_ENT="StatusWidget/StatusWidget.entitlements"
PBX="PersonalToolbox.xcodeproj/project.pbxproj"

# --- App Groups: strip unless ENABLE_APP_GROUPS=1 (profile must include the group)
if [[ "${ENABLE_APP_GROUPS:-}" != "1" ]]; then
  for f in "$MAIN_ENT" "$WIDGET_ENT"; do
    [[ -f "$f" ]] || continue
    cat > "$f" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF
  done
  echo "Stripped App Groups from entitlements (Ad Hoc profile compatibility)."
fi

# --- StatusWidget: keep only when widget profile secret is present
if [[ -z "${WIDGET_BUILD_PROVISION_PROFILE_BASE64:-}" ]]; then
  echo "No WIDGET_BUILD_PROVISION_PROFILE_BASE64 — strip StatusWidget target from archive."
  python3 - <<'PY'
from pathlib import Path
import re
pbx = Path("PersonalToolbox.xcodeproj/project.pbxproj")
text = pbx.read_text()
# Embed line
text = re.sub(
    r"\t\t\t\t[0-9A-F]{24} /\* StatusWidget\.appex in Embed Foundation Extensions \*/,\n",
    "",
    text,
)
# Main target dependency entry for StatusWidget (id 626)
text = text.replace("\t\t\t\t000000000000000000000626 /* PBXTargetDependency */,\n", "")
# Project targets list entry
text = re.sub(r"\n\t\t\t\t[0-9A-F]{24} /\* StatusWidget \*/,", "", text)
text = re.sub(r",\n\t\t\t\t[0-9A-F]{24} /\* StatusWidget \*/", "", text)
pbx.write_text(text)
print("StatusWidget removed from embed + targets + dependency.")
PY
else
  echo "Installing StatusWidget provisioning profile…"
  PP_PATH="${RUNNER_TEMP}/widget.mobileprovision"
  echo "$WIDGET_BUILD_PROVISION_PROFILE_BASE64" | base64 -d > "$PP_PATH"
  PROFILE_UUID=$(security cms -D -i "$PP_PATH" | plutil -extract UUID raw -)
  mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
  cp "$PP_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/${PROFILE_UUID}.mobileprovision"
  echo "Widget profile UUID=${PROFILE_UUID}"
  if [[ -n "${WIDGET_PROVISION_PROFILE_SPECIFIER:-}" ]]; then
    SPEC="$WIDGET_PROVISION_PROFILE_SPECIFIER"
    python3 - <<PY
from pathlib import Path
pbx = Path("PersonalToolbox.xcodeproj/project.pbxproj")
text = pbx.read_text()
needle = "PRODUCT_BUNDLE_IDENTIFIER = app.parsnip6345.lake8262.widget;"
insert = needle + "\\n\\t\\t\\t\\tPROVISIONING_PROFILE_SPECIFIER = \\"${SPEC}\\";"
if needle in text and "lake8262.widget" in text:
    # only inject once per occurrence without specifier nearby
    parts = text.split(needle)
    out = [parts[0]]
    for part in parts[1:]:
        if "PROVISIONING_PROFILE_SPECIFIER" not in part[:80]:
            out.append(insert)
        else:
            out.append(needle)
        out.append(part)
    pbx.write_text("".join(out) if False else text.replace(needle, insert))
print("Injected widget profile specifier")
PY
  fi
fi

echo "ci-strip-extensions-if-needed done."
