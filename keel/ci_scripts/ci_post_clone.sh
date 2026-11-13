#!/bin/sh
# Xcode Cloud runs this right after cloning the repo, before building.
# It regenerates Keel.xcodeproj from project.yml so the cloud build always matches the latest code.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH/keel"

brew install xcodegen

# App blocking (Screen Time / FamilyControls): Apple granted the distribution entitlement, but Xcode Cloud
# also exports an ad-hoc build, and the ad-hoc provisioning profile doesn't carry Family Controls yet, so
# that export fails (exit code 70) and takes the whole build down. Until Apple enables Family Controls for
# ad-hoc on the App ID, cloud builds leave it out (the app shows "not available in this build").
# Once fixed, set KEEL_FAMILY_CONTROLS=1 in the Xcode Cloud workflow's environment variables.
if [ "${KEEL_FAMILY_CONTROLS:-0}" != "1" ]; then
  sed -i '' '/com.apple.developer.family-controls/d' project.yml
  echo "FamilyControls entitlement left out of this build (set KEEL_FAMILY_CONTROLS=1 to include it)."
fi

# Apple Weather (WeatherKit) and Apple Health (HealthKit): the export fails if the App ID doesn't have these
# capabilities turned on yet, because the provisioning profile won't carry them. Cloud builds leave them out
# unless enabled; the app hides weather and Health features gracefully without them.
# Both are now enabled on the App ID com.briangreenejr.keel, so they're included by default.
# To leave one out (e.g. if Apple's capability setup breaks an export), set in the workflow's environment variables:
#   KEEL_WEATHERKIT=0   or   KEEL_HEALTHKIT=0
if [ "${KEEL_WEATHERKIT:-1}" != "1" ]; then
  sed -i '' '/com.apple.developer.weatherkit/d' project.yml
  echo "WeatherKit entitlement left out of this build (KEEL_WEATHERKIT=0)."
fi
# iCloud sync + Sign in with Apple need the App ID's iCloud (with container iCloud.com.briangreenejr.keel),
# Push Notifications and Sign in with Apple capabilities turned on at developer.apple.com first.
# Off until then; set KEEL_ICLOUD=1 in the Xcode Cloud workflow's environment variables to include them.
if [ "${KEEL_ICLOUD:-0}" != "1" ]; then
  sed -i '' '/KEEL_ICLOUD/d' project.yml
  sed -i '' '/com.apple.developer.applesignin/d' project.yml
  for key in com.apple.developer.icloud-container-identifiers com.apple.developer.icloud-services com.apple.developer.aps-environment com.apple.developer.applesignin; do
    /usr/libexec/PlistBuddy -c "Delete :$key" Keel/KeelMac.entitlements 2>/dev/null || true
  done
  echo "iCloud sync and Sign in with Apple left out of this build (set KEEL_ICLOUD=1 once the App ID has them)."
fi
if [ "${KEEL_HEALTHKIT:-1}" != "1" ]; then
  sed -i '' '/com.apple.developer.healthkit/d' project.yml
  echo "HealthKit entitlements left out of this build (KEEL_HEALTHKIT=0)."
fi

# Apple Watch app: it needs its own two App IDs (…watchkitapp and …watchkitapp.widgets), each with App Groups.
# Both are registered with App Groups, so the watch app is included by default.
# Set KEEL_WATCH=0 in the workflow's environment variables to ship the iPhone app without it.
if [ "${KEEL_WATCH:-1}" != "1" ]; then
  sed -i '' '/      - target: KeelWatch                 # Apple Watch companion/d' project.yml
  echo "Apple Watch app left out of this build (KEEL_WATCH=0)."
fi

# Default mail app: Apple must grant the com.apple.developer.mail-client entitlement first.
# Once it's granted, add KEEL_MAIL_CLIENT=1 to the Xcode Cloud workflow's environment variables.
if [ "${KEEL_MAIL_CLIENT:-0}" = "1" ]; then
  sed -i '' 's/^\(        com.apple.security.application-groups:.*\)$/\1\
        com.apple.developer.mail-client: true/' project.yml
  echo "Default mail app entitlement included (KEEL_MAIL_CLIENT=1)."
fi

# Every TestFlight upload needs a higher build number; use Xcode Cloud's counter.
if [ -n "$CI_BUILD_NUMBER" ]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$CI_BUILD_NUMBER\"/" project.yml
fi

xcodegen generate

# Diagnostics: show what this build will ask Apple to sign, so export failures are easy to pin down.
echo "---- Keel signing diagnostics ----"
echo "KEEL_FAMILY_CONTROLS=${KEEL_FAMILY_CONTROLS:-unset} KEEL_WEATHERKIT=${KEEL_WEATHERKIT:-unset} KEEL_HEALTHKIT=${KEEL_HEALTHKIT:-unset} KEEL_MAIL_CLIENT=${KEEL_MAIL_CLIENT:-unset}"
for f in Keel/Keel.entitlements KeelWidgets/KeelWidgets.entitlements KeelShare/KeelShare.entitlements KeelWatch/KeelWatch.entitlements KeelWatchWidgets/KeelWatchWidgets.entitlements; do
  echo "== $f"; grep -o '<key>[^<]*</key>' "$f" || true
done
grep -n "PRODUCT_BUNDLE_IDENTIFIER" project.yml || true
echo "----------------------------------"

