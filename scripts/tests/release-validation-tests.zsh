#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR:h}/lib/release-validation.zsh"

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

print "release validation tests passed"
