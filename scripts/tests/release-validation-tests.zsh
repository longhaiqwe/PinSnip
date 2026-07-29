#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR:h}/lib/release-validation.zsh"
BUILD_RELEASE_SCRIPT="${SCRIPT_DIR:h}/build-release.sh"

timestamped_signature=$'Identifier=com.longhai.pinsnip\nTimestamp=Jul 29, 2026 at 10:00:00'
untimestamped_signature=$'Identifier=com.longhai.pinsnip\nTeamIdentifier=5RFJK73RSL'
debug_entitlements=$'<key>com.apple.security.get-task-allow</key>\n<true/>'
release_entitlements=$'<dict/>\n'

release_signature_has_secure_timestamp "${timestamped_signature}"

if release_signature_has_secure_timestamp "${untimestamped_signature}"; then
  print -u2 "Expected a signature without Timestamp= to be rejected"
  exit 1
fi

release_entitlements_include_get_task_allow "${debug_entitlements}"

if release_entitlements_include_get_task_allow "${release_entitlements}"; then
  print -u2 "Expected release entitlements without get-task-allow to be accepted"
  exit 1
fi

if ! grep -Fq 'OTHER_CODE_SIGN_FLAGS="--timestamp"' "${BUILD_RELEASE_SCRIPT}"; then
  print -u2 "Expected every Xcode-managed nested release signature to request a secure timestamp"
  exit 1
fi

for sparkle_component in \
  "XPCServices/Installer.xpc" \
  "XPCServices/Downloader.xpc" \
  "Autoupdate" \
  "Updater.app"; do
  if ! grep -Fq "${sparkle_component}" "${BUILD_RELEASE_SCRIPT}"; then
    print -u2 "Expected build-release.sh to re-sign Sparkle component: ${sparkle_component}"
    exit 1
  fi
done

print "release validation tests passed"
