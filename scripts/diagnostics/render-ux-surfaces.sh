#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h:h}"
PREVIEW_BUILD="${PROJECT_DIR}/build/UXAudit"
PRODUCTS="${PREVIEW_BUILD}/DerivedData/Build/Products/Release"
if [[ ! -d "${PRODUCTS}/PinSnipCore.framework" ]]; then
  PRODUCTS="${PREVIEW_BUILD}/DerivedData/Build/Products/Debug"
fi
cd "${PROJECT_DIR}"

if [[ ! -d "${PRODUCTS}/PinSnipCore.framework" ]]; then
  print -u2 "Run the UX audit xcodebuild test command first (see docs/ui/2026-11-13-product-ux-audit.md)."
  exit 1
fi
mkdir -p "${PREVIEW_BUILD}/previews"
xcrun clang -mmacosx-version-min=14.0 -fobjc-arc -c PinSnip/Capture/LegacyScreenCapture.m \
  -o "${PREVIEW_BUILD}/LegacyScreenCapture.o"
preview_sources=("${(@f)$(rg --files PinSnip/Capture PinSnip/Hotkeys PinSnip/Output PinSnip/Pins PinSnip/Shelf -g '*.swift')}")
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  -F "${PRODUCTS}" -framework PinSnipCore \
  -import-objc-header PinSnip/Capture/LegacyScreenCapture.h \
  -Xlinker -rpath -Xlinker "${PRODUCTS}" \
  "${preview_sources[@]}" "${PREVIEW_BUILD}/LegacyScreenCapture.o" \
  scripts/diagnostics/ux-surface-preview.swift -o "${PREVIEW_BUILD}/ux-surface-preview"
"${PREVIEW_BUILD}/ux-surface-preview" "${PREVIEW_BUILD}/previews"
