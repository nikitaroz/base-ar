#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="BaseAR"
BUNDLE_ID="com.example.BaseAR"
PROJECT="$ROOT/BaseAR.xcodeproj"
DERIVED="$ROOT/build/DerivedData"
# iPhone 17 on this Mac. Used only when no iPhone simulator is already booted.
FALLBACK_UDID="7CCAD89F-B59B-4D8D-9FC7-DE7ABB1F560D"

booted_iphone_udid() {
  xcrun simctl list devices booted | awk '
    /iPhone/ && match($0, /\([A-F0-9-]{36}\)/) {
      print substr($0, RSTART + 1, RLENGTH - 2)
      exit
    }
  '
}

UDID="$(booted_iphone_udid)"
if [[ -z "${UDID}" ]]; then
  UDID="${FALLBACK_UDID}"
  echo "No iPhone simulator booted; booting ${UDID}"
  xcrun simctl boot "${UDID}"
  xcrun simctl bootstatus "${UDID}" -b
else
  echo "Using booted iPhone simulator ${UDID}"
fi

# Xcode 27 does not ship Simulator.app; the visible UI is DeviceHub.
if ! open -a Simulator 2>/dev/null; then
  DEV_DIR="$(xcode-select -p)"
  if [[ -d "${DEV_DIR}/Applications/Simulator.app" ]]; then
    open "${DEV_DIR}/Applications/Simulator.app"
  elif [[ -d "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" ]]; then
    open "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
  else
    open -a DeviceHub
  fi
fi

echo "Building ${SCHEME} (Debug, iOS Simulator) for ${UDID}"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "${DERIVED}" \
  build

APP="${DERIVED}/Build/Products/Debug-iphonesimulator/BaseAR.app"
if [[ ! -d "${APP}" ]]; then
  APP="$(find "${DERIVED}" -type d -path "*iphonesimulator*" -name "BaseAR.app" | head -n 1)"
fi
if [[ -z "${APP}" || ! -d "${APP}" ]]; then
  echo "BaseAR.app not found under ${DERIVED}" >&2
  exit 1
fi

echo "Installing ${APP}"
xcrun simctl install booted "${APP}"
xcrun simctl terminate booted "${BUNDLE_ID}" >/dev/null 2>&1 || true
xcrun simctl launch booted "${BUNDLE_ID}"
echo "Launched ${BUNDLE_ID} on booted simulator (${UDID})"
