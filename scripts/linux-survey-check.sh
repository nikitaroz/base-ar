#!/usr/bin/env bash
# Compiles the survey model, eligibility rules, and JSON exporter on Linux and
# runs three sessions: empty (incomplete), 100A breaker (conflict), and a fully
# measured pass (clear). Xcode, the simulator, camera, and AR are not involved.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc is not on PATH. The Cloud Agent image is expected to provide Swift 6.4 under /opt/swift." >&2
  exit 1
fi

OUT="${1:-/tmp/basear-survey-check}"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "Parsing Swift sources"
find BaseAR BaseARTests -name '*.swift' -print0 | xargs -0 swiftc -parse -swift-version 6

SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT

cat > "$SHIM/UIKit.swift" << 'EOF'
import Foundation

@MainActor
public class UIDevice: NSObject {
    public static let current = UIDevice()
    public var systemVersion: String { "Linux" }
    public var model: String { "Linux" }
}
EOF

# SurveyExporting imports simd. SIMD3 itself is in the Swift standard library.
# This empty module only satisfies the import; placement math stays on device.
printf '\n' > "$SHIM/simd.swift"

swiftc -swift-version 6 -parse-as-library -emit-module -emit-object -module-name UIKit \
  -emit-module-path "$SHIM/UIKit.swiftmodule" -o "$SHIM/UIKit.o" "$SHIM/UIKit.swift"
swiftc -swift-version 6 -parse-as-library -emit-module -module-name simd \
  -emit-module-path "$SHIM/simd.swiftmodule" "$SHIM/simd.swift"

BIN="$SHIM/linux-survey-check"
echo "Compiling survey model, rules, and JSON exporter"
swiftc -swift-version 6 -I "$SHIM" -o "$BIN" \
  BaseAR/Survey/SurveySession.swift \
  BaseAR/Rules/EligibilityRule.swift \
  BaseAR/Rules/BaseRuleSet.swift \
  BaseAR/Rules/SurveyEvaluating.swift \
  BaseAR/Review/SurveyExporting.swift \
  scripts/LinuxSurveyCheck.swift \
  "$SHIM/UIKit.o"

echo "Running survey sessions"
"$BIN" "$OUT"

python3 - "$OUT" << 'PY'
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
incomplete = json.loads((out / "incomplete-survey.json").read_text())
conflict = json.loads((out / "conflict-survey.json").read_text())
clear = json.loads((out / "clear-survey.json").read_text())

assert incomplete["placementTone"] == "incomplete", incomplete["placementTone"]
assert conflict["placementTone"] == "conflict", conflict["placementTone"]
assert conflict["electrical"]["mainBreakerAmperage"] == 100
assert clear["placementTone"] == "clear", clear["placementTone"]
assert clear["electrical"]["mainBreakerAmperage"] == 200
assert clear["electrical"]["plannedBatteryCount"] == 1
assert clear["electrical"]["hasSolar"] is False
assert "not an electrical inspection" in clear["prototypeDisclaimer"]
assert clear["propertyLocation"]["latitude"] == 30.2672
assert all(item["status"] == "pass" for item in clear["ruleResults"])
print("survey.json checks passed")
print(f"  incomplete rules={len(incomplete['ruleResults'])} missing={len(incomplete['missingInformation'])}")
print(f"  conflict tone={conflict['placementTone']} breaker={conflict['electrical']['mainBreakerAmperage']}A")
print(f"  clear tone={clear['placementTone']} rules={len(clear['ruleResults'])}")
PY
