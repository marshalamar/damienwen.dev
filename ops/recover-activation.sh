#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly LC_ALL="C"
export PATH LC_ALL

readonly APP_ROOT="/srv/damienwen"
readonly RELEASES_DIR="${APP_ROOT}/releases"
readonly CURRENT_LINK="${APP_ROOT}/current"
readonly LAST_KNOWN_GOOD_LINK="${APP_ROOT}/last-known-good"
readonly ACTIVATION_PENDING="${APP_ROOT}/activation-pending"
readonly BOOT_ROLE_FILE="${APP_ROOT}/boot-role"
readonly SERVICE_NAME="damienwen.service"
readonly LEGACY_SERVICE_NAME="damienwen-legacy.service"

NEXT_LINK=""
NEXT_BOOT_ROLE_FILE=""

log() {
  printf '[damienwen-recover] %s\n' "$*"
}

die() {
  printf '[damienwen-recover] error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${NEXT_LINK}" &&
    "${NEXT_LINK}" == "${APP_ROOT}/.current-recovery-"* &&
    -L "${NEXT_LINK}" ]]; then
    rm -f -- "${NEXT_LINK}"
  fi
  if [[ -n "${NEXT_BOOT_ROLE_FILE}" &&
    "${NEXT_BOOT_ROLE_FILE}" == "${APP_ROOT}/.boot-role-"* &&
    -f "${NEXT_BOOT_ROLE_FILE}" &&
    ! -L "${NEXT_BOOT_ROLE_FILE}" ]]; then
    rm -f -- "${NEXT_BOOT_ROLE_FILE}"
  fi
}

trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
trap cleanup EXIT

require_commands() {
  local command_name

  for command_name in \
    chmod chown find ln mapfile mv readlink rm sha256sum sort stat sync \
    systemctl xargs; do
    command -v "${command_name}" > /dev/null ||
      die "required command is unavailable: ${command_name}"
  done
}

compute_tree_hash() {
  local digest_line
  local directory

  directory="$1"
  digest_line="$(
    (
      cd -- "${directory}"
      find . -xdev -type f \
          ! -path './.release-tree-sha256' \
          -print0 |
        sort --zero-terminated |
        xargs --null --no-run-if-empty sha256sum --
    ) | sha256sum
  )"
  digest_line="${digest_line%% *}"
  [[ "${digest_line}" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s\n' "${digest_line}"
}

verify_release_integrity() {
  local actual_tree_hash
  local directory
  local expected_tree_hash
  local stored_artifact_hash
  local stored_sha
  local unsafe_path

  directory="$1"
  [[ -d "${directory}" && ! -L "${directory}" ]] || return 1
  [[ "${directory%/*}" == "${RELEASES_DIR}" ]] || return 1
  [[ "${directory##*/}" =~ ^[0-9a-f]{40}$ ]] || return 1

  unsafe_path="$(
    find "${directory}" -xdev -mindepth 1 \
      ! -type f ! -type d -print -quit
  )"
  [[ -z "${unsafe_path}" ]] || return 1
  unsafe_path="$(
    find "${directory}" -xdev -type f -links +1 -print -quit
  )"
  [[ -z "${unsafe_path}" ]] || return 1
  unsafe_path="$(
    find "${directory}" -xdev -mindepth 1 \
      \( ! -user root -o -perm /022 \) -print -quit
  )"
  [[ -z "${unsafe_path}" ]] || return 1

  [[ -f "${directory}/server.js" &&
    ! -L "${directory}/server.js" ]] || return 1
  [[ -f "${directory}/dist/server/index.js" &&
    ! -L "${directory}/dist/server/index.js" ]] || return 1
  [[ -f "${directory}/.release-sha" &&
    ! -L "${directory}/.release-sha" ]] || return 1
  [[ -f "${directory}/.artifact-sha256" &&
    ! -L "${directory}/.artifact-sha256" ]] || return 1
  [[ -f "${directory}/.release-tree-sha256" &&
    ! -L "${directory}/.release-tree-sha256" ]] || return 1

  IFS= read -r stored_sha < "${directory}/.release-sha" || return 1
  IFS= read -r stored_artifact_hash \
    < "${directory}/.artifact-sha256" || return 1
  IFS= read -r expected_tree_hash \
    < "${directory}/.release-tree-sha256" || return 1

  [[ "${stored_sha}" == "${directory##*/}" ]] || return 1
  [[ "${stored_artifact_hash}" =~ ^[0-9a-f]{64}$ ]] || return 1
  [[ "${expected_tree_hash}" =~ ^[0-9a-f]{64}$ ]] || return 1
  actual_tree_hash="$(compute_tree_hash "${directory}")" || return 1
  [[ "${actual_tree_hash}" == "${expected_tree_hash}" ]]
}

read_pending_record() {
  local metadata
  local -a lines

  [[ -f "${ACTIVATION_PENDING}" &&
    ! -L "${ACTIVATION_PENDING}" ]] ||
    die "activation-pending is not a regular file"
  metadata="$(stat --format='%U:%G:%a:%h:%s' -- "${ACTIVATION_PENDING}")"
  [[ "${metadata}" == "root:root:600:1:48" ||
    "${metadata}" == "root:root:600:1:51" ]] ||
    die "activation-pending has unsafe metadata"
  mapfile -t lines < "${ACTIVATION_PENDING}"
  ((${#lines[@]} == 1)) ||
    die "activation-pending must contain exactly one line"
  [[ "${lines[0]}" =~ ^([0-9a-f]{40})[[:space:]](legacy|candidate)$ ]] ||
    die "activation-pending contains an invalid release identifier"
  printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

resolve_last_known_good() {
  local target

  [[ -L "${LAST_KNOWN_GOOD_LINK}" ]] || return 1
  target="$(readlink --canonicalize "${LAST_KNOWN_GOOD_LINK}")" || return 1
  verify_release_integrity "${target}" || return 1
  printf '%s\n' "${target}"
}

set_current_link() {
  local target

  target="$1"
  verify_release_integrity "${target}" ||
    die "refusing to recover an invalid release"
  NEXT_LINK="${APP_ROOT}/.current-recovery-$$"
  ln --symbolic -- "${target}" "${NEXT_LINK}"
  mv --no-target-directory --force -- "${NEXT_LINK}" "${CURRENT_LINK}"
  sync --file-system "${APP_ROOT}"
  NEXT_LINK=""
}

clear_activation_pending() {
  rm -f -- "${ACTIVATION_PENDING}"
  sync --file-system "${APP_ROOT}"
}

read_boot_role() {
  local metadata
  local role
  local -a lines

  [[ -f "${BOOT_ROLE_FILE}" && ! -L "${BOOT_ROLE_FILE}" ]] || return 1
  metadata="$(stat --format='%U:%G:%a:%h' -- "${BOOT_ROLE_FILE}")" ||
    return 1
  [[ "${metadata}" == "root:root:644:1" ]] || return 1
  mapfile -t lines < "${BOOT_ROLE_FILE}"
  ((${#lines[@]} == 1)) || return 1
  role="${lines[0]}"
  [[ "${role}" == "managed" || "${role}" == "legacy" ]] || return 1
  printf '%s\n' "${role}"
}

persist_boot_role() {
  local role

  role="$1"
  [[ "${role}" == "managed" || "${role}" == "legacy" ]] ||
    die "invalid boot role: ${role}"

  NEXT_BOOT_ROLE_FILE="${APP_ROOT}/.boot-role-${role}-$$"
  printf '%s\n' "${role}" > "${NEXT_BOOT_ROLE_FILE}"
  chown --no-dereference root:root "${NEXT_BOOT_ROLE_FILE}"
  chmod 0644 "${NEXT_BOOT_ROLE_FILE}"
  sync "${NEXT_BOOT_ROLE_FILE}"
  mv \
    --no-target-directory \
    --force \
    -- "${NEXT_BOOT_ROLE_FILE}" "${BOOT_ROLE_FILE}"
  sync --file-system "${APP_ROOT}"
  NEXT_BOOT_ROLE_FILE=""
}

service_is_loaded() {
  [[ "$(
    systemctl show \
      --property=LoadState \
      --value \
      "$1" 2> /dev/null || true
  )" == "loaded" ]]
}

service_is_running() {
  [[ "$(
    systemctl show \
      --property=ActiveState \
      --value \
      "$1" 2> /dev/null || true
  )" == "active" ]]
}

load_or_initialize_boot_role() {
  if [[ -e "${BOOT_ROLE_FILE}" || -L "${BOOT_ROLE_FILE}" ]]; then
    read_boot_role ||
      die "boot-role marker is unsafe"
    return 0
  fi

  if [[ -L "${LAST_KNOWN_GOOD_LINK}" ]]; then
    persist_boot_role "managed"
    printf '%s\n' "managed"
    return 0
  fi
  if service_is_loaded "${LEGACY_SERVICE_NAME}" &&
    systemctl is-enabled --quiet "${LEGACY_SERVICE_NAME}"; then
    persist_boot_role "legacy"
    printf '%s\n' "legacy"
    return 0
  fi
  if service_is_loaded "${SERVICE_NAME}"; then
    persist_boot_role "managed"
    printf '%s\n' "managed"
    return 0
  fi

  # Fresh bootstrap may be interrupted after installing this recovery unit
  # but before either website unit or a role marker exists.
  printf '%s\n' ""
}

reconcile_boot_role() {
  local role

  role="$1"
  case "${role}" in
    managed)
      service_is_loaded "${SERVICE_NAME}" ||
        die "managed boot role is selected but its unit is unavailable"
      systemctl enable "${SERVICE_NAME}" > /dev/null
      if service_is_loaded "${LEGACY_SERVICE_NAME}"; then
        systemctl disable "${LEGACY_SERVICE_NAME}" > /dev/null
      fi
      ;;
    legacy)
      service_is_loaded "${LEGACY_SERVICE_NAME}" ||
        die "legacy boot role is selected but its unit is unavailable"
      systemctl enable "${LEGACY_SERVICE_NAME}" > /dev/null
      if service_is_loaded "${SERVICE_NAME}"; then
        systemctl disable "${SERVICE_NAME}" > /dev/null
      fi
      ;;
    *)
      die "invalid boot role: ${role}"
      ;;
  esac
}

transition_boot_role() {
  local role

  role="$1"
  case "${role}" in
    managed)
      service_is_loaded "${SERVICE_NAME}" ||
        die "managed unit is unavailable"
      systemctl enable "${SERVICE_NAME}" > /dev/null
      persist_boot_role "managed"
      if service_is_loaded "${LEGACY_SERVICE_NAME}"; then
        systemctl disable "${LEGACY_SERVICE_NAME}" > /dev/null
      fi
      ;;
    legacy)
      service_is_loaded "${LEGACY_SERVICE_NAME}" ||
        die "legacy unit is unavailable"
      systemctl enable "${LEGACY_SERVICE_NAME}" > /dev/null
      persist_boot_role "legacy"
      if service_is_loaded "${SERVICE_NAME}"; then
        systemctl disable "${SERVICE_NAME}" > /dev/null
      fi
      ;;
    *)
      die "invalid boot role: ${role}"
      ;;
  esac
}

ensure_boot_role_started() {
  local other
  local role
  local selected

  role="$1"
  case "${role}" in
    managed)
      selected="${SERVICE_NAME}"
      other="${LEGACY_SERVICE_NAME}"
      ;;
    legacy)
      selected="${LEGACY_SERVICE_NAME}"
      other="${SERVICE_NAME}"
      ;;
    *)
      die "invalid boot role: ${role}"
      ;;
  esac

  service_is_running "${selected}" && return 0
  if service_is_running "${other}"; then
    log \
      "left the already-running ${other} untouched while arming" \
      "${selected} for the next boot"
    return 0
  fi
  systemctl --no-block start "${selected}"
}

main() {
  local boot_role
  local candidate
  local last_known_good
  local pending_mode
  local pending_sha

  ((EUID == 0)) || die "boot recovery must run as root"
  require_commands
  umask 0027
  [[ -d "${APP_ROOT}" && ! -L "${APP_ROOT}" ]] ||
    die "application root is missing or unsafe"
  [[ -d "${RELEASES_DIR}" && ! -L "${RELEASES_DIR}" ]] ||
    die "release directory is missing or unsafe"

  if [[ -e "${CURRENT_LINK}" && ! -L "${CURRENT_LINK}" ]]; then
    die "current path exists but is not a managed symbolic link"
  fi
  if [[ -e "${LAST_KNOWN_GOOD_LINK}" &&
    ! -L "${LAST_KNOWN_GOOD_LINK}" ]]; then
    die "last-known-good path exists but is not a managed symbolic link"
  fi

  boot_role="$(load_or_initialize_boot_role)"
  if [[ -z "${boot_role}" ]]; then
    log "no website unit or persisted boot role is installed yet"
    return 0
  fi
  reconcile_boot_role "${boot_role}"
  ensure_boot_role_started "${boot_role}"

  if [[ ! -e "${ACTIVATION_PENDING}" &&
    ! -L "${ACTIVATION_PENDING}" ]]; then
    log "reconciled ${boot_role} boot role; no activation is pending"
    return 0
  fi

  IFS=$'\t' read -r pending_sha pending_mode \
    < <(read_pending_record) ||
    die "could not read activation-pending"
  if [[ -L "${LAST_KNOWN_GOOD_LINK}" ]]; then
    last_known_good="$(resolve_last_known_good)" ||
      die "last-known-good link is broken or failed integrity verification"
    set_current_link "${last_known_good}"
    transition_boot_role "managed"
    systemctl --no-block start "${SERVICE_NAME}"
    clear_activation_pending
    log "restored last-known-good release ${last_known_good##*/}"
    return 0
  fi

  if [[ "${pending_mode}" == "legacy" ]] &&
    service_is_loaded "${LEGACY_SERVICE_NAME}"; then
    transition_boot_role "legacy"
    systemctl --no-block start "${LEGACY_SERVICE_NAME}"
    log \
      "kept activation pending; the persisted legacy role remains the" \
      "first-migration boot fallback"
    return 0
  fi

  candidate="${RELEASES_DIR}/${pending_sha}"
  verify_release_integrity "${candidate}" ||
    die "pending candidate is invalid and no boot fallback is available"
  set_current_link "${candidate}"
  transition_boot_role "managed"
  systemctl --no-block start "${SERVICE_NAME}"
  log \
    "retained preflighted candidate ${pending_sha};" \
    "activation remains pending until a production health check passes"
}

main "$@"
