release_signature_has_secure_timestamp() {
  local signature_details="$1"
  [[ "${signature_details}" == *"Timestamp="* ]]
}

release_entitlements_include_get_task_allow() {
  local entitlements="$1"
  [[ "${entitlements}" == *"com.apple.security.get-task-allow"* ]]
}
