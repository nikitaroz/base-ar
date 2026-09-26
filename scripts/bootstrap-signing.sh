#!/usr/bin/env bash
# Creates Config/Local.xcconfig with the current user's Apple development Team ID
# and a bundle identifier derived from their macOS username, so builds sign correctly
# without hand-editing. Safe to re-run: bails out if Local.xcconfig already exists.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="$repo_root/Config"
local_config="$config_dir/Local.xcconfig"
example_config="$config_dir/Local.xcconfig.example"

if [ -f "$local_config" ]; then
  echo "Config/Local.xcconfig already exists. Not overwriting."
  cat "$local_config"
  exit 0
fi

if [ ! -f "$example_config" ]; then
  echo "Config/Local.xcconfig.example is missing. Repo layout has changed." >&2
  exit 1
fi

identity_line=$(security find-identity -v -p codesigning | grep -E '"Apple Development: ' | head -1 || true)
if [ -z "$identity_line" ]; then
  cat >&2 <<'MSG'
No Apple Development code-signing identity found in this Mac's keychain.

Do this once, then re-run:
  1. Open Xcode.
  2. Xcode -> Settings -> Accounts.
  3. Click + and sign in with your Apple ID.
  4. Xcode will download an Apple Development certificate for you.

If you'd rather set this up manually, copy Config/Local.xcconfig.example
to Config/Local.xcconfig and fill in DEVELOPMENT_TEAM + PRODUCT_BUNDLE_IDENTIFIER
by hand.
MSG
  exit 1
fi

team_id=$(printf '%s' "$identity_line" | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p')
if [ -z "$team_id" ]; then
  echo "Could not parse a 10-character Team ID from: $identity_line" >&2
  exit 1
fi

username_slug=$(whoami | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
if [ -z "$username_slug" ]; then
  username_slug="developer"
fi
bundle_id="com.${username_slug}.BaseAR"

cat > "$local_config" <<EOF
DEVELOPMENT_TEAM = $team_id
PRODUCT_BUNDLE_IDENTIFIER = $bundle_id
EOF

echo "Wrote $local_config:"
cat "$local_config"
echo
echo "If Xcode still can't find a matching provisioning profile, sign in to Xcode -> Settings -> Accounts once, then build with:"
echo "  xcodebuild -project BaseAR.xcodeproj -scheme BaseAR -destination 'generic/platform=iOS' -allowProvisioningUpdates build"
