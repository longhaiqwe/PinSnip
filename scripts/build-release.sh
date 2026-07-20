#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="${PROJECT_DIR}/build/Release"
PINSNIP_SIGNING_IDENTITY="${PINSNIP_CODE_SIGN_IDENTITY:-Developer ID Application: hai long (5RFJK73RSL)}"
PINSNIP_SIGNING_TEAM="${PINSNIP_DEVELOPMENT_TEAM:-5RFJK73RSL}"

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
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${PINSNIP_SIGNING_IDENTITY}" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM="${PINSNIP_SIGNING_TEAM}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${OUTPUT_DIR}/PinSnip.app"

print "Built ${OUTPUT_DIR}/PinSnip.app"
