#!/bin/bash
# Archive Keel and upload it to TestFlight from this Mac, without Xcode Cloud (no compute hours used).
# It prepares the project exactly like Xcode Cloud does (ci_post_clone.sh: same entitlements left out, same
# build-number rule), in a temporary copy of the repo, so your working copy and project.yml stay untouched.
#
#   keel/ci_scripts/testflight_from_mac.sh <build-number>            archive, then upload to App Store Connect
#   CHECK=1 keel/ci_scripts/testflight_from_mac.sh <build-number>    prepare and compile only (unsigned, no upload)
#   ARCHIVE_ONLY=1 keel/ci_scripts/testflight_from_mac.sh <build>    signed archive, no upload
#
# The build number must be higher than the last one in App Store Connect (Xcode Cloud's last was 235).
# Signing: either sign in to Xcode (Settings → Accounts, team NT3YQF6DM5), or use an App Store Connect API key:
#   ASC_KEY_PATH=/path/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=xxxxxxxx-... keel/ci_scripts/testflight_from_mac.sh 236
# Same environment switches as the Xcode Cloud workflow (KEEL_ICLOUD, KEEL_SAFARI, KEEL_WATCH, …) apply.
set -euo pipefail

BUILD="${1:?usage: testflight_from_mac.sh <build-number>}"
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "Build number must be a whole number." >&2; exit 1; }
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
WORK="$TMP/repo"
OUT="${OUT:-$HOME/Desktop/Keel-$BUILD}"

git -C "$ROOT" worktree add --detach --quiet "$WORK" HEAD
cleanup() { local s=$?; git -C "$ROOT" worktree remove --force "$WORK" 2>/dev/null || true; rm -rf "$TMP"; exit $s; }
trap cleanup EXIT
echo "Preparing build $BUILD from commit $(git -C "$WORK" rev-parse --short HEAD)…"

# Exactly what Xcode Cloud runs after cloning (minus installing XcodeGen, which this Mac already has).
command -v xcodegen >/dev/null || { echo "XcodeGen is needed: brew install xcodegen" >&2; exit 1; }
sed '/brew install xcodegen/d' "$WORK/keel/ci_scripts/ci_post_clone.sh" > "$TMP/post_clone.sh"
CI_PRIMARY_REPOSITORY_PATH="$WORK" CI_BUILD_NUMBER="$BUILD" bash "$TMP/post_clone.sh" > "$TMP/post_clone.log"
grep -E "left out|included" "$TMP/post_clone.log" || true
cd "$WORK/keel"

AUTH=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "${ASC_KEY_ID:?set ASC_KEY_ID}" -authenticationKeyIssuerID "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}")
fi

if [[ "${CHECK:-0}" == "1" ]]; then
  xcodebuild -project Keel.xcodeproj -scheme Keel -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$TMP/dd" CODE_SIGNING_ALLOWED=NO build -quiet
  echo "Check passed: build $BUILD compiles with Xcode Cloud's settings. Nothing was signed or uploaded."
  exit 0
fi

mkdir -p "$OUT"
xcodebuild -project Keel.xcodeproj -scheme Keel -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Keel.xcarchive" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} archive -quiet
echo "Archived: $OUT/Keel.xcarchive"
if [[ "${ARCHIVE_ONLY:-0}" == "1" ]]; then echo "ARCHIVE_ONLY=1: signed archive made, nothing uploaded."; exit 0; fi

cat > "$TMP/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>NT3YQF6DM5</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Keel.xcarchive" -exportOptionsPlist "$TMP/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}
echo "Uploaded build $BUILD to App Store Connect. It appears in TestFlight after Apple finishes processing (usually 5–30 minutes)."
