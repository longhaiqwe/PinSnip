#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="${PROJECT_DIR}/build/Release"
PINSNIP_VERSION="$(tr -d '[:space:]' < "${PROJECT_DIR}/VERSION")"
PINSNIP_SIGNING_IDENTITY="${PINSNIP_CODE_SIGN_IDENTITY:-}"
PINSNIP_SIGNING_TEAM="${PINSNIP_DEVELOPMENT_TEAM:-}"
source "${SCRIPT_DIR}/lib/release-validation.zsh"

require_universal_binary() {
  local binary_path="$1"
  local label="$2"
  local architectures

  if [[ ! -f "${binary_path}" ]]; then
    print -u2 "Missing ${label}: ${binary_path}"
    exit 2
  fi

  architectures="$(/usr/bin/lipo -archs "${binary_path}")"
  for required_architecture in arm64 x86_64; do
    if [[ " ${architectures} " != *" ${required_architecture} "* ]]; then
      print -u2 "${label} is not Universal: ${architectures}"
      exit 2
    fi
  done
  print "${label} architectures: ${architectures}"
}

cd "${PROJECT_DIR}"
xcodegen generate
xcodebuild test \
  -project PinSnip.xcodeproj \
  -scheme PinSnip \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

release_settings=(
  ARCHS="arm64 x86_64"
  ONLY_ACTIVE_ARCH=NO
  CONFIGURATION_BUILD_DIR="${OUTPUT_DIR}"
)

if [[ -n "${PINSNIP_SIGNING_IDENTITY}" ]]; then
  release_settings+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="${PINSNIP_SIGNING_IDENTITY}"
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_REQUIRED=YES
    OTHER_CODE_SIGN_FLAGS="--timestamp"
  )
  if [[ -n "${PINSNIP_SIGNING_TEAM}" ]]; then
    release_settings+=(DEVELOPMENT_TEAM="${PINSNIP_SIGNING_TEAM}")
  fi
else
  release_settings+=(CODE_SIGNING_ALLOWED=NO)
fi

xcodebuild build \
  -project PinSnip.xcodeproj \
  -scheme PinSnip \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  "${release_settings[@]}"

APP_PATH="${OUTPUT_DIR}/PinSnip.app"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/PinSnip"
CORE_EXECUTABLE="${APP_PATH}/Contents/Frameworks/PinSnipCore.framework/Versions/A/PinSnipCore"
SPARKLE_FRAMEWORK="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="${SPARKLE_FRAMEWORK}/Versions/B"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"

if [[ "${BUILT_VERSION}" != "${PINSNIP_VERSION}" ]]; then
  print -u2 "Version mismatch: VERSION=${PINSNIP_VERSION}, app=${BUILT_VERSION}"
  exit 2
fi

require_universal_binary "${APP_EXECUTABLE}" "PinSnip"
require_universal_binary "${CORE_EXECUTABLE}" "PinSnipCore"

if [[ -n "${PINSNIP_SIGNING_IDENTITY}" ]]; then
  /usr/bin/codesign \
    --force \
    --sign "${PINSNIP_SIGNING_IDENTITY}" \
    --options runtime \
    --timestamp \
    "${SPARKLE_VERSION}/XPCServices/Installer.xpc"
  /usr/bin/codesign \
    --force \
    --sign "${PINSNIP_SIGNING_IDENTITY}" \
    --options runtime \
    --timestamp \
    --preserve-metadata=entitlements \
    "${SPARKLE_VERSION}/XPCServices/Downloader.xpc"
  /usr/bin/codesign \
    --force \
    --sign "${PINSNIP_SIGNING_IDENTITY}" \
    --options runtime \
    --timestamp \
    "${SPARKLE_VERSION}/Autoupdate"
  /usr/bin/codesign \
    --force \
    --sign "${PINSNIP_SIGNING_IDENTITY}" \
    --options runtime \
    --timestamp \
    "${SPARKLE_VERSION}/Updater.app"
  /usr/bin/codesign \
    --force \
    --sign "${PINSNIP_SIGNING_IDENTITY}" \
    --options runtime \
    --timestamp \
    "${SPARKLE_FRAMEWORK}"
  /usr/bin/codesign \
    --force \
    --sign "${PINSNIP_SIGNING_IDENTITY}" \
    --options runtime \
    --timestamp \
    "${APP_PATH}/Contents/Frameworks/PinSnipCore.framework"
  /usr/bin/codesign \
    --force \
    --sign "${PINSNIP_SIGNING_IDENTITY}" \
    --options runtime \
    --timestamp \
    "${APP_PATH}"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

  release_signed_components=(
    "${SPARKLE_VERSION}/XPCServices/Installer.xpc"
    "${SPARKLE_VERSION}/XPCServices/Downloader.xpc"
    "${SPARKLE_VERSION}/Autoupdate"
    "${SPARKLE_VERSION}/Updater.app"
    "${SPARKLE_FRAMEWORK}"
    "${APP_PATH}/Contents/Frameworks/PinSnipCore.framework"
    "${APP_PATH}"
  )
  for signed_component in "${release_signed_components[@]}"; do
    release_entitlements="$(/usr/bin/codesign -d --entitlements :- "${signed_component}" 2>&1)"
    if release_entitlements_include_get_task_allow "${release_entitlements}"; then
      print -u2 "Release component contains the debug get-task-allow entitlement: ${signed_component}"
      exit 2
    fi
    signature_details="$(/usr/bin/codesign -dvvv "${signed_component}" 2>&1)"
    if ! release_signature_has_secure_timestamp "${signature_details}"; then
      print -u2 "Release component is missing a secure signing timestamp: ${signed_component}"
      exit 2
    fi
  done
fi

print "Built PinSnip ${PINSNIP_VERSION}: ${APP_PATH}"
