#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="${PROJECT_DIR}/build/Release"

cd "${PROJECT_DIR}"
xcodegen generate
xcodebuild test \
  -project PinSnip.xcodeproj \
  -scheme PinSnip \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build \
  -project PinSnip.xcodeproj \
  -scheme PinSnip \
  -configuration Release \
  -destination 'platform=macOS' \
  CONFIGURATION_BUILD_DIR="${OUTPUT_DIR}" \
  CODE_SIGNING_ALLOWED=NO

print "Built ${OUTPUT_DIR}/PinSnip.app"
