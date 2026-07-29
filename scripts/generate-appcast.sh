#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
ARCHIVE_DIR="${1:-${PROJECT_DIR}/build/Release}"
PINSNIP_VERSION="$(tr -d '[:space:]' < "${PROJECT_DIR}/VERSION")"
ARCHIVE_NAME="PinSnip-v${PINSNIP_VERSION}-macOS-universal.zip"
ARCHIVE_PATH="${ARCHIVE_DIR}/${ARCHIVE_NAME}"
RELEASE_NOTES_PATH="${ARCHIVE_DIR}/PinSnip-v${PINSNIP_VERSION}-release-notes.md"
APPCAST_PATH="${PINSNIP_APPCAST_PATH:-${PROJECT_DIR}/appcast.xml}"
DOWNLOAD_URL_PREFIX="${PINSNIP_DOWNLOAD_URL_PREFIX:-https://github.com/longhaiqwe/PinSnip/releases/download/v${PINSNIP_VERSION}/}"

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  print -u2 "Missing release archive: ${ARCHIVE_PATH}"
  exit 2
fi

cd "${PROJECT_DIR}"
xcodegen generate
xcodebuild -resolvePackageDependencies \
  -project PinSnip.xcodeproj \
  -scheme PinSnip >/dev/null

BUILD_DIR="$(
  xcodebuild -showBuildSettings \
    -project PinSnip.xcodeproj \
    -scheme PinSnip \
    -configuration Release 2>/dev/null |
    sed -n 's/^[[:space:]]*BUILD_DIR = //p' |
    head -1
)"
DERIVED_DATA_DIR="$(dirname "$(dirname "${BUILD_DIR}")")"
GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-${DERIVED_DATA_DIR}/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast}"
GENERATE_KEYS="${GENERATE_APPCAST:h}/generate_keys"

if [[ ! -x "${GENERATE_APPCAST}" ]]; then
  print -u2 "Sparkle generate_appcast tool not found: ${GENERATE_APPCAST}"
  exit 2
fi
if [[ ! -x "${GENERATE_KEYS}" ]]; then
  print -u2 "Sparkle generate_keys tool not found: ${GENERATE_KEYS}"
  exit 2
fi

umask 077
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pinsnip-appcast.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT
PRIVATE_KEY_PATH="${WORK_DIR}/sparkle-private-key"

cp "${ARCHIVE_PATH}" "${WORK_DIR}/${ARCHIVE_NAME}"
ARCHIVE_INFO_PLIST="${WORK_DIR}/archive-info.plist"
unzip -p "${ARCHIVE_PATH}" "PinSnip.app/Contents/Info.plist" > "${ARCHIVE_INFO_PLIST}"
ARCHIVE_PUBLIC_KEY="$(
  /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${ARCHIVE_INFO_PLIST}" 2>/dev/null || true
)"
SOURCE_PUBLIC_KEY="$(
  /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' \
    "${PROJECT_DIR}/PinSnip/Resources/Info.plist"
)"
if [[ -z "${ARCHIVE_PUBLIC_KEY}" || "${ARCHIVE_PUBLIC_KEY}" != "${SOURCE_PUBLIC_KEY}" ]]; then
  print -u2 "Release archive is missing PinSnip's current Sparkle public key"
  exit 2
fi
if [[ -f "${RELEASE_NOTES_PATH}" ]]; then
  cp "${RELEASE_NOTES_PATH}" "${WORK_DIR}/${ARCHIVE_NAME:r}.md"
fi
if [[ -f "${APPCAST_PATH}" ]]; then
  cp "${APPCAST_PATH}" "${WORK_DIR}/appcast.xml"
fi

"${GENERATE_KEYS}" -x "${PRIVATE_KEY_PATH}" >/dev/null
"${GENERATE_APPCAST}" \
  --ed-key-file "${PRIVATE_KEY_PATH}" \
  --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
  --link "https://github.com/longhaiqwe/PinSnip" \
  --maximum-versions 10 \
  --maximum-deltas 0 \
  -o "${WORK_DIR}/appcast.xml" \
  "${WORK_DIR}"

if ! grep -q "edSignature" "${WORK_DIR}/appcast.xml"; then
  print -u2 "Generated appcast is missing an EdDSA signature"
  exit 2
fi
if ! grep -q "${ARCHIVE_NAME}" "${WORK_DIR}/appcast.xml"; then
  print -u2 "Generated appcast is missing ${ARCHIVE_NAME}"
  exit 2
fi

cp "${WORK_DIR}/appcast.xml" "${APPCAST_PATH}"
print "Generated signed appcast: ${APPCAST_PATH}"
