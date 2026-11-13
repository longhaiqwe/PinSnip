#!/bin/bash
set -euo pipefail
# Usage: script SOURCE_ROOT MATCHING_RELEASE_PRODUCTS OUTPUT_BINARY [ENTRY_SWIFT]
source_root="${1:?Source snapshot required}"
products="${2:?Matching Release products required}"
output="${3:?Output binary required}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
entry="${4:-$script_dir/capture-startup-benchmark.swift}"
mkdir -p "$(dirname "$output")"
xcrun clang -mmacosx-version-min=14.0 -Wno-deprecated-declarations -c \
  "$source_root/PinSnip/Capture/LegacyScreenCapture.m" -o "$output-quartz.o"
extra_flags=(-O)
if rg -q 'func prewarm\(' "$source_root/PinSnip/Capture/ScreenCaptureService.swift"; then
  extra_flags+=(-D CAPTURE_PREWARM)
fi
xcrun swiftc "${extra_flags[@]}" -swift-version 6 -target "$(uname -m)-apple-macos14.0" -parse-as-library \
  -F "$products" -framework PinSnipCore -Xlinker -rpath -Xlinker "$products" \
  -import-objc-header "$source_root/PinSnip/Capture/LegacyScreenCapture.h" \
  "$source_root/PinSnip/Capture/ScreenCaptureService.swift" \
  "$source_root/PinSnip/Capture/WindowDetector.swift" \
  "$source_root/PinSnip/Capture/SelectionOverlayView.swift" \
  "$source_root/PinSnip/Capture/SelectionOverlayController.swift" \
  "$source_root/PinSnip/Capture/TextAnnotationEditorView.swift" \
  "$entry" "$output-quartz.o" -o "$output"
