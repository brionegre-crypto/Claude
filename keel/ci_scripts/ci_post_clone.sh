#!/bin/sh
# Xcode Cloud runs this right after cloning the repo, before building.
# It regenerates Keel.xcodeproj from project.yml so the cloud build always matches the latest code.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH/keel"

brew install xcodegen

# App blocking (Screen Time / FamilyControls): Apple granted the distribution entitlement, so cloud builds
# include it. Escape hatch: set KEEL_FAMILY_CONTROLS=0 in the Xcode Cloud workflow to build without it.
if [ "${KEEL_FAMILY_CONTROLS:-1}" = "0" ]; then
  sed -i '' '/com.apple.developer.family-controls/d' project.yml
  echo "FamilyControls entitlement removed for this build (KEEL_FAMILY_CONTROLS=0)."
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
