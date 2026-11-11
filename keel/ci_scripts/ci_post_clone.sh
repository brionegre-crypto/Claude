#!/bin/sh
# Xcode Cloud runs this right after cloning the repo, before building.
# It regenerates Keel.xcodeproj from project.yml so the cloud build always matches the latest code.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH/keel"

brew install xcodegen

# App blocking (Screen Time / FamilyControls) needs Apple's distribution approval before it can ship
# through TestFlight. Until it's granted, leave the entitlement out of cloud builds. After Apple approves,
# add an environment variable KEEL_FAMILY_CONTROLS=1 to the Xcode Cloud workflow.
if [ "${KEEL_FAMILY_CONTROLS:-0}" != "1" ]; then
  sed -i '' '/com.apple.developer.family-controls/d' project.yml
  echo "FamilyControls entitlement removed for this build (set KEEL_FAMILY_CONTROLS=1 once Apple approves it)."
fi

# Every TestFlight upload needs a higher build number; use Xcode Cloud's counter.
if [ -n "$CI_BUILD_NUMBER" ]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$CI_BUILD_NUMBER\"/" project.yml
fi

xcodegen generate
