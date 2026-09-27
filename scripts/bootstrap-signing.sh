#!/usr/bin/env bash
# One-time signing setup per Mac.
#
# Writes Config/Local.xcconfig (gitignored) with this developer's Apple Team ID and a
# personal bundle identifier, and turns on the repo's git hooks so a Team ID never gets
# committed into BaseAR.xcodeproj. Safe to re-run: an existing Local.xcconfig is kept.
#
# Usage: ./scripts/bootstrap-signing.sh [TEAM_ID]
#   Pass TEAM_ID when your certificates belong to more than one team.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_config="$repo_root/Config/Local.xcconfig"

# Shared hooks live in .githooks; the pre-commit hook rejects a committed DEVELOPMENT_TEAM.
git -C "$repo_root" config core.hooksPath .githooks
echo "Git hooks enabled (.githooks)."

if [ -f "$local_config" ]; then
  echo "Config/Local.xcconfig already exists. Not overwriting:"
  cat "$local_config"
  exit 0
fi

# The Team ID is the certificate's OU field. The ID in parentheses in the certificate
# name is a personal identifier and often differs from the team, so it is not used.
teams=$(
  security find-certificate -a -c "Apple Development:" -p 2>/dev/null \
    | awk '/BEGIN CERTIFICATE/{cert=""} {cert=cert $0 "\n"} /END CERTIFICATE/{printf "%s", cert | "openssl x509 -noout -subject"; close("openssl x509 -noout -subject")}' \
    | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' \
    | sort -u
)

if [ $# -ge 1 ]; then
  team_id="$1"
elif [ -z "$teams" ]; then
  cat >&2 <<'MSG'
No Apple Development certificate found in this Mac's keychain.

Do this once, then re-run:
  1. Open Xcode -> Settings -> Accounts.
  2. Click + and sign in with your Apple ID.
  3. Select the team and click "Manage Certificates..." -> + -> Apple Development.

Or copy Config/Local.xcconfig.example to Config/Local.xcconfig and fill it in by hand.
MSG
  exit 1
elif [ "$(printf '%s\n' "$teams" | wc -l | tr -d ' ')" -gt 1 ]; then
  echo "Certificates for more than one team were found:" >&2
  printf '  %s\n' $teams >&2
  echo "Re-run with the one to use: ./scripts/bootstrap-signing.sh TEAM_ID" >&2
  exit 1
else
  team_id="$teams"
fi

if ! printf '%s' "$team_id" | grep -qE '^[A-Z0-9]{10}$'; then
  echo "\"$team_id\" is not a 10-character Team ID." >&2
  exit 1
fi

# Bundle IDs are global across Apple accounts, so each developer needs their own.
username_slug=$(whoami | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
bundle_id="com.${username_slug:-developer}.BaseAR"

cat > "$local_config" <<EOF
// Personal signing settings. Gitignored; never commit this file.
DEVELOPMENT_TEAM = $team_id
PRODUCT_BUNDLE_IDENTIFIER = $bundle_id
EOF

echo "Wrote $local_config:"
cat "$local_config"
echo
echo "Build for a device with:"
echo "  xcodebuild -project BaseAR.xcodeproj -scheme BaseAR -destination 'generic/platform=iOS' -allowProvisioningUpdates build"
