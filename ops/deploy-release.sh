#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly LC_ALL="C"
export PATH LC_ALL

readonly APP_USER="damienwen"
readonly APP_GROUP="damienwen"
readonly EXTRACT_USER="damienwen-extract"
readonly EXTRACT_GROUP="damienwen-extract"
readonly DEPLOY_USER="damienwen-deploy"
readonly APP_ROOT="/srv/damienwen"
readonly INCOMING_DIR="${APP_ROOT}/incoming"
readonly RELEASES_DIR="${APP_ROOT}/releases"
readonly STAGING_ROOT="${APP_ROOT}/staging"
readonly TRANSACTIONS_DIR="${APP_ROOT}/transactions"
readonly KNOWN_GOOD_DIR="${APP_ROOT}/known-good"
readonly CURRENT_LINK="${APP_ROOT}/current"
readonly LAST_KNOWN_GOOD_LINK="${APP_ROOT}/last-known-good"
readonly ACTIVATION_PENDING="${APP_ROOT}/activation-pending"
readonly BOOT_ROLE_FILE="${APP_ROOT}/boot-role"
readonly LOCK_FILE="/run/lock/damienwen-deploy.lock"
readonly SERVICE_NAME="damienwen.service"
readonly LEGACY_SERVICE_NAME="damienwen-legacy.service"
readonly PRODUCTION_URL="http://127.0.0.1:3000/"
readonly PREFLIGHT_PORT="3100"
readonly PREFLIGHT_URL="http://127.0.0.1:${PREFLIGHT_PORT}/"
readonly PRODUCTION_HEALTH_ATTEMPTS=30
readonly PREFLIGHT_HEALTH_ATTEMPTS=20
readonly RECENT_KNOWN_GOOD_TO_KEEP=4
readonly MAX_ARCHIVE_MEMBERS=10000
readonly MAX_ARCHIVE_FILE_BYTES=$((64 * 1024 * 1024))
readonly MAX_ARCHIVE_LOGICAL_BYTES=$((512 * 1024 * 1024))
readonly MAX_INCOMING_ARCHIVE_BYTES=$((128 * 1024 * 1024))
readonly MAX_INCOMING_CHECKSUM_BYTES=1024
readonly INCOMING_READ_TIMEOUT_SECONDS=30
readonly STALE_WORK_MINUTES=1440

RELEASE_SHA=""
RELEASE_DIR=""
ARCHIVE_PATH=""
CHECKSUM_PATH=""
ARTIFACT_HASH=""
INCOMING_ARTIFACT_HASH=""
PREVIOUS_RELEASE=""
LAST_KNOWN_GOOD_RELEASE=""
STAGING_DIR=""
TRANSACTION_DIR=""
NEXT_LINK=""
NEXT_KNOWN_GOOD_LINK=""
NEXT_PENDING_FILE=""
NEXT_BOOT_ROLE_FILE=""
PREFLIGHT_UNIT=""
SWITCHED=0
ROLLBACK_DONE=0
DEPLOYMENT_COMPLETE=0
INCOMING_PRESENT=0
PRODUCTION_RESTART_ATTEMPTED=0
LEGACY_FALLBACK_AVAILABLE=0
ACTIVATION_FALLBACK_MODE=""
LOCK_FD=""
INCOMING_LOCK_FD=""

log() {
  printf '[damienwen-deploy] %s\n' "$*"
}

die() {
  printf '[damienwen-deploy] error: %s\n' "$*" >&2
  exit 1
}

path_has_prefix() {
  local path
  local prefix

  path="$1"
  prefix="$2"
  [[ "${path}" == "${prefix}"* ]]
}

cleanup_preflight() {
  if [[ -n "${PREFLIGHT_UNIT}" ]]; then
    systemctl stop "${PREFLIGHT_UNIT}" > /dev/null 2>&1 || true
    systemctl reset-failed "${PREFLIGHT_UNIT}" > /dev/null 2>&1 || true
    PREFLIGHT_UNIT=""
  fi
}

cleanup_temporary_files() {
  local expected_prefix

  cleanup_preflight

  expected_prefix="${STAGING_ROOT}/.staging-${RELEASE_SHA}-"
  if [[ -n "${STAGING_DIR}" ]] &&
    path_has_prefix "${STAGING_DIR}" "${expected_prefix}" &&
    [[ -d "${STAGING_DIR}" ]]; then
    rm -rf --one-file-system -- "${STAGING_DIR}"
  fi

  expected_prefix="${TRANSACTIONS_DIR}/${RELEASE_SHA}-"
  if [[ -n "${TRANSACTION_DIR}" ]] &&
    path_has_prefix "${TRANSACTION_DIR}" "${expected_prefix}" &&
    [[ -d "${TRANSACTION_DIR}" ]]; then
    rm -rf --one-file-system -- "${TRANSACTION_DIR}"
  fi

  expected_prefix="${APP_ROOT}/.current-${RELEASE_SHA}-"
  if [[ -n "${NEXT_LINK}" ]] &&
    path_has_prefix "${NEXT_LINK}" "${expected_prefix}" &&
    [[ -L "${NEXT_LINK}" ]]; then
    rm -f -- "${NEXT_LINK}"
  fi

  expected_prefix="${APP_ROOT}/.last-known-good-"
  if [[ -n "${NEXT_KNOWN_GOOD_LINK}" ]] &&
    path_has_prefix "${NEXT_KNOWN_GOOD_LINK}" "${expected_prefix}" &&
    [[ -L "${NEXT_KNOWN_GOOD_LINK}" ]]; then
    rm -f -- "${NEXT_KNOWN_GOOD_LINK}"
  fi

  expected_prefix="${APP_ROOT}/.activation-pending-"
  if [[ -n "${NEXT_PENDING_FILE}" ]] &&
    path_has_prefix "${NEXT_PENDING_FILE}" "${expected_prefix}" &&
    [[ -f "${NEXT_PENDING_FILE}" && ! -L "${NEXT_PENDING_FILE}" ]]; then
    rm -f -- "${NEXT_PENDING_FILE}"
  fi

  expected_prefix="${APP_ROOT}/.boot-role-"
  if [[ -n "${NEXT_BOOT_ROLE_FILE}" ]] &&
    path_has_prefix "${NEXT_BOOT_ROLE_FILE}" "${expected_prefix}" &&
    [[ -f "${NEXT_BOOT_ROLE_FILE}" && ! -L "${NEXT_BOOT_ROLE_FILE}" ]]; then
    rm -f -- "${NEXT_BOOT_ROLE_FILE}"
  fi
}

require_commands() {
  local command_name

  for command_name in \
    awk chmod chown cp curl cut date find flock head id journalctl ln mkdir \
    mktemp mv readlink rm runuser sha256sum sleep sort stat sync systemctl \
    systemd-run tar timeout touch xargs; do
    command -v "${command_name}" > /dev/null ||
      die "required command is unavailable: ${command_name}"
  done
}

acquire_deploy_lock() {
  exec {LOCK_FD}> "${LOCK_FILE}"
  if ! flock --exclusive --nonblock "${LOCK_FD}"; then
    die "another deployment transaction is already running"
  fi
}

acquire_incoming_lock() {
  exec {INCOMING_LOCK_FD}< "${INCOMING_DIR}"
  if ! flock --exclusive --wait 5 "${INCOMING_LOCK_FD}"; then
    die "an upload transaction is still active"
  fi
}

validate_server_layout() {
  local directory
  local extractor_uid
  local runtime_uid
  local staging_metadata

  for directory in \
    "${APP_ROOT}" \
    "${INCOMING_DIR}" \
    "${RELEASES_DIR}" \
    "${STAGING_ROOT}" \
    "${TRANSACTIONS_DIR}" \
    "${KNOWN_GOOD_DIR}"; do
    [[ -d "${directory}" && ! -L "${directory}" ]] ||
      die "required deployment directory is missing or unsafe: ${directory}"
  done

  runtime_uid="$(id --user "${APP_USER}")" ||
    die "runtime account is unavailable: ${APP_USER}"
  extractor_uid="$(id --user "${EXTRACT_USER}")" ||
    die "extractor account is unavailable: ${EXTRACT_USER}"
  [[ "${runtime_uid}" != "${extractor_uid}" ]] ||
    die "runtime and extractor must use different user IDs"
  [[ "$(id --group --name "${EXTRACT_USER}")" == "${EXTRACT_GROUP}" ]] ||
    die "extractor account has an unexpected primary group"

  staging_metadata="$(stat --format='%U:%G:%a' -- "${STAGING_ROOT}")"
  [[ "${staging_metadata}" == "root:${EXTRACT_GROUP}:710" ]] ||
    die "private staging directory has unexpected ownership or mode"
  if runuser --user "${APP_USER}" -- /usr/bin/test -x "${STAGING_ROOT}"; then
    die "runtime account must not be able to traverse private staging"
  fi
}

cleanup_stale_work_directories() {
  local current_target
  local last_known_good_target
  local pending_sha
  local path
  local path_name

  current_target="$(
    readlink --canonicalize "${CURRENT_LINK}" 2> /dev/null || true
  )"
  last_known_good_target="$(
    readlink --canonicalize "${LAST_KNOWN_GOOD_LINK}" 2> /dev/null || true
  )"
  pending_sha=""
  if path_exists_or_is_link "${ACTIVATION_PENDING}"; then
    pending_sha="$(read_activation_pending_sha)" ||
      die "activation-pending marker is unsafe"
  fi

  while IFS= read -r -d '' path; do
    path_name="${path##*/}"
    [[ "${path%/*}" == "${INCOMING_DIR}" ]] || continue
    if [[ ! "${path_name}" =~ ^\.upload-[A-Za-z0-9]{6}$ &&
      ! "${path_name}" =~ ^[0-9a-f]{40}\.tar\.gz(\.sha256)?$ ]]; then
      continue
    fi
    log "removing stale incoming upload ${path_name}"
    rm -f -- "${path}"
  done < <(
    find "${INCOMING_DIR}" -xdev -mindepth 1 -maxdepth 1 \
      \( -type f -o -type l \) \
      -mmin "+${STALE_WORK_MINUTES}" -print0
  )

  while IFS= read -r -d '' path; do
    path_name="${path##*/}"
    [[ "${path%/*}" == "${STAGING_ROOT}" ]] || continue
    [[ "${path_name}" =~ ^\.staging-[0-9a-f]{40}-[A-Za-z0-9]+$ ]] ||
      continue
    log "removing stale extraction directory ${path_name}"
    rm -rf --one-file-system -- "${path}"
  done < <(
    find "${STAGING_ROOT}" -xdev -mindepth 1 -maxdepth 1 \
      -type d -mmin "+${STALE_WORK_MINUTES}" -print0
  )

  while IFS= read -r -d '' path; do
    path_name="${path##*/}"
    [[ "${path%/*}" == "${TRANSACTIONS_DIR}" ]] || continue
    [[ "${path_name}" =~ ^[0-9a-f]{40}-[A-Za-z0-9]+$ ]] || continue
    log "removing stale deployment transaction ${path_name}"
    rm -rf --one-file-system -- "${path}"
  done < <(
    find "${TRANSACTIONS_DIR}" -xdev -mindepth 1 -maxdepth 1 \
      -type d -mmin "+${STALE_WORK_MINUTES}" -print0
  )

  while IFS= read -r -d '' path; do
    path_name="${path##*/}"
    [[ "${path%/*}" == "${RELEASES_DIR}" ]] || continue
    [[ "${path_name}" =~ ^[0-9a-f]{40}$ ]] || continue
    [[ "${path_name}" != "${RELEASE_SHA}" ]] || continue
    [[ "${path_name}" != "${pending_sha}" ]] || continue
    [[ "${path}" != "${current_target}" ]] || continue
    [[ "${path}" != "${last_known_good_target}" ]] || continue
    has_safe_known_good_marker "${path_name}" && continue

    log "removing stale unretained release ${path_name}"
    rm -rf --one-file-system -- "${path}"
  done < <(
    find "${RELEASES_DIR}" -xdev -mindepth 1 -maxdepth 1 \
      -type d -mmin "+${STALE_WORK_MINUTES}" -print0
  )
}

path_exists_or_is_link() {
  [[ -e "$1" || -L "$1" ]]
}

assert_regular_single_link_file() {
  local link_count
  local path

  path="$1"
  [[ -f "${path}" && ! -L "${path}" ]] ||
    die "refusing a symlink or non-regular upload: ${path##*/}"
  link_count="$(stat --format='%h' -- "${path}")" ||
    die "could not inspect uploaded file: ${path##*/}"
  [[ "${link_count}" == "1" ]] ||
    die "refusing a multiply-linked upload: ${path##*/}"
}

copy_incoming_file() {
  local destination
  local limit
  local size
  local source

  source="$1"
  destination="$2"
  limit="$3"

  : > "${destination}"
  chown --no-dereference root:root "${destination}"
  chmod 0600 "${destination}"

  if ! runuser --user "${DEPLOY_USER}" -- \
    timeout \
      --signal=KILL \
      "${INCOMING_READ_TIMEOUT_SECONDS}" \
      head \
        --bytes="$((limit + 1))" \
        -- "${source}" > "${destination}"; then
    die "could not read bounded incoming upload: ${source##*/}"
  fi

  assert_regular_single_link_file "${destination}"
  size="$(stat --format='%s' -- "${destination}")"
  ((size > 0)) || die "incoming upload is empty: ${source##*/}"
  ((size <= limit)) ||
    die "incoming upload exceeds its allowed size: ${source##*/}"
}

claim_incoming_files() {
  local incoming_archive
  local incoming_checksum

  incoming_archive="${INCOMING_DIR}/${RELEASE_SHA}.tar.gz"
  incoming_checksum="${incoming_archive}.sha256"

  if path_exists_or_is_link "${incoming_archive}" &&
    path_exists_or_is_link "${incoming_checksum}"; then
    TRANSACTION_DIR="$(
      mktemp --directory "${TRANSACTIONS_DIR}/${RELEASE_SHA}-XXXXXX"
    )"
    chmod 0700 "${TRANSACTION_DIR}"

    ARCHIVE_PATH="${TRANSACTION_DIR}/${RELEASE_SHA}.tar.gz"
    CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
    copy_incoming_file \
      "${incoming_archive}" \
      "${ARCHIVE_PATH}" \
      "${MAX_INCOMING_ARCHIVE_BYTES}"
    copy_incoming_file \
      "${incoming_checksum}" \
      "${CHECKSUM_PATH}" \
      "${MAX_INCOMING_CHECKSUM_BYTES}"

    # These names are removed only after root owns independent bounded copies.
    # A writer retaining an old incoming file descriptor cannot alter either
    # transaction inode.
    rm -f -- "${incoming_archive}" "${incoming_checksum}"
    INCOMING_PRESENT=1
    return 0
  fi

  if path_exists_or_is_link "${incoming_archive}" ||
    path_exists_or_is_link "${incoming_checksum}"; then
    die "incoming release is incomplete; archive and checksum must both exist"
  fi
}

verify_incoming_archive() {
  local actual_hash
  local checksum_filename
  local checksum_line
  local expected_hash

  assert_regular_single_link_file "${ARCHIVE_PATH}"
  assert_regular_single_link_file "${CHECKSUM_PATH}"

  IFS= read -r checksum_line < "${CHECKSUM_PATH}" ||
    die "could not read release checksum"

  if [[ ! "${checksum_line}" =~ ^([0-9a-f]{64})[[:space:]]+(\*?)([^[:space:]]+)$ ]]; then
    die "release checksum has an unexpected format"
  fi

  expected_hash="${BASH_REMATCH[1]}"
  checksum_filename="${BASH_REMATCH[3]}"
  [[ "${checksum_filename}" == "${RELEASE_SHA}.tar.gz" ]] ||
    die "release checksum names an unexpected file"

  actual_hash="$(sha256sum "${ARCHIVE_PATH}")"
  actual_hash="${actual_hash%% *}"
  [[ "${actual_hash}" == "${expected_hash}" ]] ||
    die "release archive checksum does not match"

  ARTIFACT_HASH="${actual_hash}"
}

validate_archive_members() {
  local archive_summary
  local member

  if ! tar \
    --list \
    --gzip \
    --quoting-style=escape \
    --file "${ARCHIVE_PATH}" |
    (
      declare -A seen_members=()
      declare -i member_count=0

      while IFS= read -r member; do
        member="${member#./}"
        if [[ -z "${member}" || "${member}" == "." ]]; then
          continue
        fi

        ((member_count += 1))
        ((member_count <= MAX_ARCHIVE_MEMBERS)) ||
          die "release archive exceeds ${MAX_ARCHIVE_MEMBERS} members"

        if [[ "${member}" == /* || "${member}" == ".." ||
          "${member}" == ../* || "${member}" == */../* ||
          "${member}" == */.. || "${member}" == *$'\n'* ||
          "${member}" == *\\* ]]; then
          die "release archive contains an unsafe path: ${member}"
        fi

        [[ -z "${seen_members[${member}]+present}" ]] ||
          die "release archive contains a duplicate path: ${member}"
        seen_members["${member}"]=1
      done

      ((member_count > 0)) || die "release archive is empty"
    ); then
    die "release archive member validation failed"
  fi

  archive_summary="$(
    tar \
      --list \
      --verbose \
      --gzip \
      --numeric-owner \
      --quoting-style=escape \
      --file "${ARCHIVE_PATH}" |
      awk \
        -v max_file="${MAX_ARCHIVE_FILE_BYTES}" \
        -v max_total="${MAX_ARCHIVE_LOGICAL_BYTES}" \
        -v max_members="${MAX_ARCHIVE_MEMBERS}" '
          BEGIN {
            count = 0
            total = 0
          }
          {
            count += 1
            if (count > max_members) {
              print "too many archive members" > "/dev/stderr"
              exit 1
            }

            type = substr($1, 1, 1)
            if (type != "-" && type != "d") {
              print "unsupported archive member type: " type > "/dev/stderr"
              exit 1
            }

            size = $3
            if (size !~ /^[0-9]+$/) {
              print "could not parse archive member size" > "/dev/stderr"
              exit 1
            }
            if (size > max_file) {
              print "archive member exceeds per-file limit" > "/dev/stderr"
              exit 1
            }

            total += size
            if (total > max_total) {
              print "archive exceeds total logical-size limit" > "/dev/stderr"
              exit 1
            }
          }
          END {
            if (count == 0) {
              print "archive is empty" > "/dev/stderr"
              exit 1
            }
            if (count <= max_members && total <= max_total) {
              printf "%d %d\n", count, total
            }
          }
        '
  )" || die "release archive type or logical-size validation failed"

  log \
    "validated archive (${archive_summary%% *} members," \
    "${archive_summary##* } logical bytes)"
}

validate_extracted_tree_shape() {
  local path
  local relative_path
  local unsafe_path

  unsafe_path="$(
    find "${STAGING_DIR}" -xdev -mindepth 1 \
      ! -type f ! -type d -print -quit
  )"
  [[ -z "${unsafe_path}" ]] ||
    die "release contains a symlink or special file: ${unsafe_path}"

  unsafe_path="$(
    find "${STAGING_DIR}" -xdev -type f -links +1 -print -quit
  )"
  [[ -z "${unsafe_path}" ]] ||
    die "release contains a hard-linked file: ${unsafe_path}"

  while IFS= read -r -d '' path; do
    relative_path="${path#"${STAGING_DIR}/"}"
    if [[ "${relative_path}" == *$'\n'* || "${relative_path}" == *\\* ]]; then
      die "release contains an unsupported filename"
    fi
  done < <(find "${STAGING_DIR}" -xdev -mindepth 1 -print0)
}

compute_tree_hash() {
  local directory
  local digest_line

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

finalize_release_permissions() {
  local tree_hash

  printf '%s\n' "${RELEASE_SHA}" > "${STAGING_DIR}/.release-sha"
  printf '%s\n' "${ARTIFACT_HASH}" > "${STAGING_DIR}/.artifact-sha256"

  chown -R root:"${APP_GROUP}" "${STAGING_DIR}"
  find "${STAGING_DIR}" -xdev -type d -exec chmod 0550 {} +
  find "${STAGING_DIR}" -xdev -type f -exec chmod 0440 {} +

  tree_hash="$(compute_tree_hash "${STAGING_DIR}")" ||
    die "could not compute release integrity hash"
  printf '%s\n' "${tree_hash}" > "${STAGING_DIR}/.release-tree-sha256"
  chown root:"${APP_GROUP}" "${STAGING_DIR}/.release-tree-sha256"
  chmod 0440 "${STAGING_DIR}/.release-tree-sha256"
}

extract_release() {
  STAGING_DIR="$(
    mktemp --directory "${STAGING_ROOT}/.staging-${RELEASE_SHA}-XXXXXX"
  )"
  chown "${EXTRACT_USER}:${EXTRACT_GROUP}" "${STAGING_DIR}"
  chmod 0700 "${STAGING_DIR}"

  # The root shell opens the claimed archive and streams it over stdin.
  # The no-login extractor is distinct from the long-running web process, and
  # the runtime user cannot traverse the private staging parent.
  if ! runuser --user "${EXTRACT_USER}" -- \
    tar \
      --extract \
      --gzip \
      --file - \
      --directory "${STAGING_DIR}" \
      --no-same-owner \
      --no-same-permissions < "${ARCHIVE_PATH}"; then
    die "release archive extraction failed"
  fi

  # Revoke the extractor's access before root inspects any archive-created
  # path. The extractor cannot replace this top-level directory because its
  # parent is root-owned and not group-writable.
  chown --no-dereference root:root "${STAGING_DIR}"
  chmod 0700 "${STAGING_DIR}"

  [[ -f "${STAGING_DIR}/server.js" &&
    ! -L "${STAGING_DIR}/server.js" ]] ||
    die "standalone server.js is missing from the release"
  [[ -f "${STAGING_DIR}/dist/server/index.js" &&
    ! -L "${STAGING_DIR}/dist/server/index.js" ]] ||
    die "standalone server bundle is missing from the release"

  validate_extracted_tree_shape
  finalize_release_permissions

  mv --no-target-directory -- "${STAGING_DIR}" "${RELEASE_DIR}"
  STAGING_DIR=""
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

  unsafe_path="$(
    find "${directory}" -xdev -mindepth 1 \
      \( ! -user root -o -perm /022 \) -print -quit
  )"
  [[ -z "${unsafe_path}" ]] || return 1

  actual_tree_hash="$(compute_tree_hash "${directory}")" || return 1
  [[ "${actual_tree_hash}" == "${expected_tree_hash}" ]] || return 1

  ARTIFACT_HASH="${stored_artifact_hash}"
}

set_current_link() {
  local target

  target="$1"
  verify_release_integrity "${target}" ||
    die "refusing to activate a release that failed integrity verification"

  NEXT_LINK="${APP_ROOT}/.current-${RELEASE_SHA}-$$"
  ln --symbolic -- "${target}" "${NEXT_LINK}"
  mv --no-target-directory --force -- "${NEXT_LINK}" "${CURRENT_LINK}"
  sync --file-system "${APP_ROOT}"
  NEXT_LINK=""
}

switch_current() {
  set_current_link "$1"
  SWITCHED=1
}

resolve_release_link() {
  local link
  local target

  link="$1"
  [[ -L "${link}" ]] || return 1
  target="$(readlink --canonicalize "${link}")" || return 1
  verify_release_integrity "${target}" || return 1
  printf '%s\n' "${target}"
}

load_last_known_good() {
  if [[ -L "${LAST_KNOWN_GOOD_LINK}" ]]; then
    LAST_KNOWN_GOOD_RELEASE="$(
      resolve_release_link "${LAST_KNOWN_GOOD_LINK}"
    )" || die "last-known-good link is broken or failed integrity verification"
  elif [[ -e "${LAST_KNOWN_GOOD_LINK}" ]]; then
    die "last-known-good path exists but is not a managed symbolic link"
  fi
}

wait_for_unit_health() {
  local attempts
  local attempt
  local healthy_streak
  local unit
  local url

  url="$1"
  attempts="$2"
  unit="$3"

  healthy_streak=0
  for ((attempt = 1; attempt <= attempts; attempt += 1)); do
    if systemctl is-active --quiet "${unit}" &&
      curl --fail --silent --max-time 2 "${url}" > /dev/null &&
      systemctl is-active --quiet "${unit}"; then
      ((healthy_streak += 1))
      if ((healthy_streak >= 2)); then
        return 0
      fi
    else
      healthy_streak=0
    fi
    sleep 1
  done

  return 1
}

preflight_release() {
  PREFLIGHT_UNIT="damienwen-preflight-${RELEASE_SHA:0:12}.service"

  systemctl stop "${PREFLIGHT_UNIT}" > /dev/null 2>&1 || true
  systemctl reset-failed "${PREFLIGHT_UNIT}" > /dev/null 2>&1 || true

  log "preflighting release ${RELEASE_SHA} on ${PREFLIGHT_URL}"
  if ! systemd-run \
    --unit="${PREFLIGHT_UNIT}" \
    --collect \
    --quiet \
    --service-type=exec \
    --property="User=${APP_USER}" \
    --property="Group=${APP_GROUP}" \
    --property="WorkingDirectory=${RELEASE_DIR}" \
    --property="NoNewPrivileges=yes" \
    --property="PrivateTmp=yes" \
    --property="ProtectSystem=strict" \
    --property="ProtectHome=yes" \
    --property="InaccessiblePaths=${INCOMING_DIR} ${STAGING_ROOT} ${TRANSACTIONS_DIR}" \
    --setenv="NODE_ENV=production" \
    --setenv="HOST=127.0.0.1" \
    --setenv="PORT=${PREFLIGHT_PORT}" \
    /usr/bin/node "${RELEASE_DIR}/server.js"; then
    die "could not start standalone preflight unit"
  fi

  if ! wait_for_unit_health \
    "${PREFLIGHT_URL}" \
    "${PREFLIGHT_HEALTH_ATTEMPTS}" \
    "${PREFLIGHT_UNIT}"; then
    journalctl \
      --unit "${PREFLIGHT_UNIT}" \
      --lines 30 \
      --no-pager >&2 || true
    die "standalone preflight failed; production was not switched or restarted"
  fi

  systemctl stop "${PREFLIGHT_UNIT}" > /dev/null
  systemctl reset-failed "${PREFLIGHT_UNIT}" > /dev/null 2>&1 || true
  PREFLIGHT_UNIT=""
  log "standalone preflight passed"
}

restart_production() {
  PRODUCTION_RESTART_ATTEMPTED=1
  transition_service_boot_role "managed" || return 1

  if ((LEGACY_FALLBACK_AVAILABLE == 1)) &&
    systemctl is-active --quiet "${LEGACY_SERVICE_NAME}"; then
    log "stopping active legacy fallback before production activation"
    systemctl stop "${LEGACY_SERVICE_NAME}"
  fi

  systemctl restart "${SERVICE_NAME}"
}

remove_managed_current_link() {
  if [[ -L "${CURRENT_LINK}" ]]; then
    rm -f -- "${CURRENT_LINK}"
    sync --file-system "${APP_ROOT}"
  elif [[ -e "${CURRENT_LINK}" ]]; then
    die "current path exists but is not a managed symbolic link"
  fi
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
  if path_exists_or_is_link "${BOOT_ROLE_FILE}"; then
    read_boot_role > /dev/null ||
      die "boot-role marker is unsafe"
  fi

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

load_or_initialize_boot_role() {
  if path_exists_or_is_link "${BOOT_ROLE_FILE}"; then
    read_boot_role > /dev/null ||
      die "boot-role marker is unsafe"
    return 0
  fi

  if [[ -n "${LAST_KNOWN_GOOD_RELEASE}" ]] ||
    ((LEGACY_FALLBACK_AVAILABLE == 0)); then
    persist_boot_role "managed"
  else
    persist_boot_role "legacy"
  fi
}

reconcile_service_boot_role() {
  local role

  role="$(read_boot_role)" || die "boot-role marker is unsafe"
  case "${role}" in
    managed)
      systemctl enable "${SERVICE_NAME}" > /dev/null || return 1
      if ((LEGACY_FALLBACK_AVAILABLE == 1)); then
        systemctl disable "${LEGACY_SERVICE_NAME}" > /dev/null || return 1
      fi
      ;;
    legacy)
      ((LEGACY_FALLBACK_AVAILABLE == 1)) || return 1
      systemctl enable "${LEGACY_SERVICE_NAME}" > /dev/null || return 1
      systemctl disable "${SERVICE_NAME}" > /dev/null || return 1
      ;;
  esac
}

transition_service_boot_role() {
  local role

  role="$1"
  case "${role}" in
    managed)
      systemctl enable "${SERVICE_NAME}" > /dev/null || return 1
      persist_boot_role "managed" || return 1
      if ((LEGACY_FALLBACK_AVAILABLE == 1)); then
        systemctl disable "${LEGACY_SERVICE_NAME}" > /dev/null || return 1
      fi
      ;;
    legacy)
      ((LEGACY_FALLBACK_AVAILABLE == 1)) || return 1
      systemctl enable "${LEGACY_SERVICE_NAME}" > /dev/null || return 1
      persist_boot_role "legacy" || return 1
      systemctl disable "${SERVICE_NAME}" > /dev/null || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

complete_service_migration() {
  transition_service_boot_role "managed"
}

persist_legacy_boot_fallback() {
  ((LEGACY_FALLBACK_AVAILABLE == 1)) || return 1
  transition_service_boot_role "legacy"
}

restore_legacy_service() {
  local candidate_release
  local candidate_selected
  local pending_candidate
  local pending_sha

  ((LEGACY_FALLBACK_AVAILABLE == 1)) || return 1

  log "restoring preserved legacy service"
  candidate_release=""
  candidate_selected=0
  pending_candidate=""
  pending_sha=""
  if path_exists_or_is_link "${ACTIVATION_PENDING}"; then
    pending_sha="$(read_activation_pending_sha)" ||
      die "activation-pending marker is unsafe before legacy restore"
    pending_candidate="${RELEASES_DIR}/${pending_sha}"
    verify_release_integrity "${pending_candidate}" ||
      die "pending candidate failed integrity verification before legacy restore"
  fi
  if [[ -L "${CURRENT_LINK}" ]]; then
    candidate_release="$(resolve_release_link "${CURRENT_LINK}")" ||
      die "current release failed integrity verification before legacy restore"
    if [[ -n "${pending_candidate}" &&
      "${candidate_release}" != "${pending_candidate}" ]]; then
      die "current release does not match the pending activation"
    fi
    candidate_selected=1
  elif [[ -e "${CURRENT_LINK}" ]]; then
    die "current path exists but is not a managed symbolic link"
  elif [[ -n "${pending_candidate}" ]]; then
    candidate_release="${pending_candidate}"
    candidate_selected=1
  fi

  systemctl stop "${SERVICE_NAME}" > /dev/null 2>&1 || true
  persist_legacy_boot_fallback || return 1

  if systemctl start "${LEGACY_SERVICE_NAME}" &&
    wait_for_unit_health \
      "${PRODUCTION_URL}" \
      "${PRODUCTION_HEALTH_ATTEMPTS}" \
      "${LEGACY_SERVICE_NAME}"; then
    remove_managed_current_link
    clear_activation_pending
    log "preserved legacy service is healthy"
    return 0
  fi

  log "critical: preserved legacy service did not recover" >&2
  systemctl stop "${LEGACY_SERVICE_NAME}" > /dev/null 2>&1 || true
  if ((candidate_selected == 1)); then
    ACTIVATION_FALLBACK_MODE="candidate"
    mark_activation_pending \
      "${candidate_release##*/}" \
      "${ACTIVATION_FALLBACK_MODE}"
    set_current_link "${candidate_release}"
    if complete_service_migration &&
      systemctl restart "${SERVICE_NAME}" &&
      wait_for_unit_health \
        "${PRODUCTION_URL}" \
        "${PRODUCTION_HEALTH_ATTEMPTS}" \
        "${SERVICE_NAME}"; then
      mark_release_known_good "${candidate_release}"
      clear_activation_pending
      log \
        "legacy recovery failed; the verified candidate remains selected" \
        "and has recovered as the new rollback baseline" >&2
    else
      log \
        "critical: neither the legacy service nor the selected candidate" \
        "recovered" >&2
    fi
  fi
  return 1
}

rollback_current() {
  if ((ROLLBACK_DONE == 1)); then
    return 0
  fi
  ROLLBACK_DONE=1

  if [[ -n "${PREVIOUS_RELEASE}" ]]; then
    log "restoring previous release ${PREVIOUS_RELEASE##*/}"
    switch_current "${PREVIOUS_RELEASE}"
    if systemctl restart "${SERVICE_NAME}" &&
      wait_for_unit_health \
        "${PRODUCTION_URL}" \
      "${PRODUCTION_HEALTH_ATTEMPTS}" \
        "${SERVICE_NAME}" &&
      complete_service_migration; then
      clear_activation_pending
      log "previous release is healthy"
      return 0
    fi

    log "critical: previous release did not recover" >&2
    return 1
  fi

  if ((PRODUCTION_RESTART_ATTEMPTED == 0)); then
    remove_managed_current_link
    log "no prior standalone release; legacy process was left untouched" >&2
    return 0
  fi

  if restore_legacy_service; then
    return 0
  fi

  log \
    "critical: no prior standalone or usable legacy fallback exists;" \
    "keeping the verified candidate selected so systemd can retry it" >&2
  return 1
}

mark_release_known_good() {
  local marker
  local release
  local sha

  release="$1"
  verify_release_integrity "${release}" ||
    die "refusing to mark an invalid release as known-good"
  sha="${release##*/}"

  marker="${KNOWN_GOOD_DIR}/${sha}"
  if path_exists_or_is_link "${marker}"; then
    has_safe_known_good_marker "${sha}" ||
      die "known-good marker exists with unsafe metadata"
  else
    touch "${marker}"
    chown --no-dereference root:root "${marker}"
    chmod 0600 "${marker}"
  fi
  touch "${marker}"
  sync "${marker}"

  NEXT_KNOWN_GOOD_LINK="${APP_ROOT}/.last-known-good-${sha}-$$"
  ln --symbolic -- "${release}" "${NEXT_KNOWN_GOOD_LINK}"
  mv \
    --no-target-directory \
    --force \
    -- "${NEXT_KNOWN_GOOD_LINK}" "${LAST_KNOWN_GOOD_LINK}"
  sync --file-system "${APP_ROOT}"
  NEXT_KNOWN_GOOD_LINK=""
  LAST_KNOWN_GOOD_RELEASE="${release}"
}

has_safe_known_good_marker() {
  local marker
  local metadata

  marker="${KNOWN_GOOD_DIR}/$1"
  [[ -f "${marker}" && ! -L "${marker}" ]] || return 1
  metadata="$(stat --format='%U:%G:%a:%h' -- "${marker}")" || return 1
  [[ "${metadata}" == "root:root:600:1" ]]
}

read_activation_pending_record() {
  local metadata
  local -a lines

  [[ -f "${ACTIVATION_PENDING}" &&
    ! -L "${ACTIVATION_PENDING}" ]] || return 1
  metadata="$(stat --format='%U:%G:%a:%h:%s' -- "${ACTIVATION_PENDING}")" ||
    return 1
  [[ "${metadata}" == "root:root:600:1:48" ||
    "${metadata}" == "root:root:600:1:51" ]] || return 1
  mapfile -t lines < "${ACTIVATION_PENDING}"
  ((${#lines[@]} == 1)) || return 1
  [[ "${lines[0]}" =~ ^([0-9a-f]{40})[[:space:]](legacy|candidate)$ ]] ||
    return 1
  printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

read_activation_pending_sha() {
  local mode
  local sha

  IFS=$'\t' read -r sha mode < <(read_activation_pending_record) || return 1
  printf '%s\n' "${sha}"
}

read_activation_pending_mode() {
  local mode
  local sha

  IFS=$'\t' read -r sha mode < <(read_activation_pending_record) || return 1
  printf '%s\n' "${mode}"
}

mark_activation_pending() {
  local fallback_mode
  local release_sha

  release_sha="$1"
  fallback_mode="$2"
  [[ "${release_sha}" =~ ^[0-9a-f]{40}$ ]] ||
    die "invalid pending release identifier: ${release_sha}"
  [[ "${fallback_mode}" == "legacy" ||
    "${fallback_mode}" == "candidate" ]] ||
    die "invalid activation fallback mode: ${fallback_mode}"
  verify_release_integrity "${RELEASES_DIR}/${release_sha}" ||
    die "refusing to persist an invalid pending release"
  if path_exists_or_is_link "${ACTIVATION_PENDING}"; then
    read_activation_pending_record > /dev/null ||
      die "an earlier activation-pending marker is unsafe"
  fi

  NEXT_PENDING_FILE="${APP_ROOT}/.activation-pending-${release_sha}-$$"
  printf '%s %s\n' \
    "${release_sha}" \
    "${fallback_mode}" > "${NEXT_PENDING_FILE}"
  chown --no-dereference root:root "${NEXT_PENDING_FILE}"
  chmod 0600 "${NEXT_PENDING_FILE}"
  sync "${NEXT_PENDING_FILE}"
  mv \
    --no-target-directory \
    --force \
    -- "${NEXT_PENDING_FILE}" "${ACTIVATION_PENDING}"
  sync --file-system "${APP_ROOT}"
  NEXT_PENDING_FILE=""
}

clear_activation_pending() {
  if [[ ! -e "${ACTIVATION_PENDING}" &&
    ! -L "${ACTIVATION_PENDING}" ]]; then
    return 0
  fi
  read_activation_pending_record > /dev/null ||
    die "refusing to remove an unsafe activation-pending marker"
  rm -f -- "${ACTIVATION_PENDING}"
  sync --file-system "${APP_ROOT}"
}

cleanup_failed_candidate() {
  local current_target
  local last_known_good_target
  local pending_sha

  [[ -n "${RELEASE_DIR}" &&
    "${RELEASE_DIR%/*}" == "${RELEASES_DIR}" &&
    "${RELEASE_DIR##*/}" =~ ^[0-9a-f]{40}$ &&
    -d "${RELEASE_DIR}" &&
    ! -L "${RELEASE_DIR}" ]] || return 0

  current_target="$(
    readlink --canonicalize "${CURRENT_LINK}" 2> /dev/null || true
  )"
  last_known_good_target="$(
    readlink --canonicalize "${LAST_KNOWN_GOOD_LINK}" 2> /dev/null || true
  )"
  pending_sha=""
  if path_exists_or_is_link "${ACTIVATION_PENDING}"; then
    pending_sha="$(read_activation_pending_sha)" || {
      log \
        "warning: kept failed release because activation-pending is unsafe" \
        >&2
      return 0
    }
  fi
  [[ "${RELEASE_DIR}" != "${current_target}" ]] || return 0
  [[ "${RELEASE_DIR}" != "${last_known_good_target}" ]] || return 0
  [[ "${RELEASE_DIR##*/}" != "${pending_sha}" ]] || return 0
  has_safe_known_good_marker "${RELEASE_SHA}" && return 0

  log "removing failed unretained release ${RELEASE_SHA}"
  rm -rf --one-file-system -- "${RELEASE_DIR}"
}

recover_interrupted_activation() {
  local candidate
  local current_target
  local pending_mode
  local pending_sha
  local restart_required

  current_target=""
  restart_required=0
  pending_mode=""
  pending_sha=""
  if path_exists_or_is_link "${ACTIVATION_PENDING}"; then
    pending_sha="$(read_activation_pending_sha)" ||
      die "activation-pending marker is unsafe"
    pending_mode="$(read_activation_pending_mode)" ||
      die "activation-pending marker is unsafe"
    ACTIVATION_FALLBACK_MODE="${pending_mode}"
    log "recovering interrupted activation ${pending_sha}"
  elif ((LEGACY_FALLBACK_AVAILABLE == 1)); then
    ACTIVATION_FALLBACK_MODE="legacy"
  else
    ACTIVATION_FALLBACK_MODE="candidate"
  fi
  if [[ -L "${CURRENT_LINK}" ]]; then
    current_target="$(resolve_release_link "${CURRENT_LINK}")" ||
      die "current release link is broken or failed integrity verification"
  elif [[ -e "${CURRENT_LINK}" ]]; then
    die "current path exists but is not a managed symbolic link"
  fi

  if [[ -n "${LAST_KNOWN_GOOD_RELEASE}" ]]; then
    PREVIOUS_RELEASE="${LAST_KNOWN_GOOD_RELEASE}"
    if [[ "${current_target}" != "${LAST_KNOWN_GOOD_RELEASE}" ]]; then
      log \
        "recovering last-known-good release" \
        "${LAST_KNOWN_GOOD_RELEASE##*/} after an incomplete activation"
      set_current_link "${LAST_KNOWN_GOOD_RELEASE}"
      restart_required=1
    fi

    if ((restart_required == 1)) ||
      ! wait_for_unit_health \
        "${PRODUCTION_URL}" \
        "${PRODUCTION_HEALTH_ATTEMPTS}" \
        "${SERVICE_NAME}"; then
      systemctl restart "${SERVICE_NAME}"
      wait_for_unit_health \
        "${PRODUCTION_URL}" \
        "${PRODUCTION_HEALTH_ATTEMPTS}" \
        "${SERVICE_NAME}" ||
        die "last-known-good release did not recover"
    fi
    complete_service_migration ||
      die "could not restore managed service boot configuration"
    clear_activation_pending
    return 0
  fi

  if [[ -z "${current_target}" ]]; then
    if ((LEGACY_FALLBACK_AVAILABLE == 0)); then
      return 0
    fi

    if [[ "${pending_mode}" == "candidate" ]]; then
      candidate="${RELEASES_DIR}/${pending_sha}"
      verify_release_integrity "${candidate}" ||
        die "pending candidate failed integrity verification"
      set_current_link "${candidate}"
      complete_service_migration ||
        die "could not select candidate after legacy fallback failure"
      if systemctl restart "${SERVICE_NAME}" &&
        wait_for_unit_health \
          "${PRODUCTION_URL}" \
          "${PRODUCTION_HEALTH_ATTEMPTS}" \
          "${SERVICE_NAME}"; then
        mark_release_known_good "${candidate}"
        PREVIOUS_RELEASE="${candidate}"
        clear_activation_pending
      else
        log \
          "candidate remains unconfirmed after the legacy fallback failed;" \
          "a new deployment may replace it" >&2
      fi
      return 0
    fi

    if systemctl is-active --quiet "${LEGACY_SERVICE_NAME}" &&
      wait_for_unit_health \
        "${PRODUCTION_URL}" \
        "${PRODUCTION_HEALTH_ATTEMPTS}" \
        "${LEGACY_SERVICE_NAME}"; then
      persist_legacy_boot_fallback ||
        die "could not persist legacy service boot configuration"
      clear_activation_pending
      return 0
    fi
    if systemctl is-active --quiet "${SERVICE_NAME}" &&
      wait_for_unit_health \
        "${PRODUCTION_URL}" \
        "${PRODUCTION_HEALTH_ATTEMPTS}" \
        "${SERVICE_NAME}"; then
      persist_legacy_boot_fallback ||
        die "could not persist legacy service boot configuration"
      clear_activation_pending
      return 0
    fi

    log "recovering legacy service after an incomplete migration transaction"
    restore_legacy_service ||
      die "legacy service did not recover after an incomplete transaction"
    return 0
  fi

  if ((LEGACY_FALLBACK_AVAILABLE == 1)); then
    if has_safe_known_good_marker "${current_target##*/}"; then
      mark_release_known_good "${current_target}"
      PREVIOUS_RELEASE="${current_target}"
      if systemctl is-active --quiet "${SERVICE_NAME}" &&
        wait_for_unit_health \
          "${PRODUCTION_URL}" \
          "${PRODUCTION_HEALTH_ATTEMPTS}" \
          "${SERVICE_NAME}"; then
        complete_service_migration ||
          die "could not persist managed service boot configuration"
      fi
      log \
        "adopted existing known-good release" \
        "${current_target##*/} as the persistent rollback baseline"
      clear_activation_pending
      return 0
    fi

    if [[ "${pending_mode}" == "candidate" ]]; then
      if systemctl is-active --quiet "${SERVICE_NAME}" &&
        wait_for_unit_health \
          "${PRODUCTION_URL}" \
          "${PRODUCTION_HEALTH_ATTEMPTS}" \
          "${SERVICE_NAME}"; then
        complete_service_migration ||
          die "could not persist managed service boot configuration"
        mark_release_known_good "${current_target}"
        PREVIOUS_RELEASE="${current_target}"
        clear_activation_pending
        log \
          "recorded recovered candidate ${current_target##*/}" \
          "after the legacy fallback failed"
      else
        log \
          "legacy fallback is known unusable and the current candidate is" \
          "still unconfirmed; a new deployment may replace it" >&2
      fi
      return 0
    fi

    log "recovering legacy service after an incomplete first activation"
    restore_legacy_service ||
      die "legacy service did not recover after an incomplete activation"
    return 0
  fi

  # A fresh VPS has no older process to restore. If the interrupted candidate
  # is already serving two consecutive healthy checks, persist it as the
  # first rollback baseline; otherwise it is deliberately not trusted.
  if wait_for_unit_health \
    "${PRODUCTION_URL}" \
    "${PRODUCTION_HEALTH_ATTEMPTS}" \
    "${SERVICE_NAME}"; then
    complete_service_migration ||
      die "could not persist managed service boot configuration"
    mark_release_known_good "${current_target}"
    PREVIOUS_RELEASE="${current_target}"
    clear_activation_pending
    log \
      "recorded healthy release ${current_target##*/}" \
      "after an interrupted first activation"
  else
    log \
      "unconfirmed current release ${current_target##*/} is unhealthy;" \
      "it will not be used as a rollback baseline" >&2
  fi
}

prune_old_releases() {
  local active_release
  local active_sha
  local candidate
  local kept_recent
  local marker
  local release_path
  local sha
  local -a markers
  local -a releases
  local -A keep

  active_release="$(readlink --canonicalize "${CURRENT_LINK}")" ||
    die "cannot resolve active release before pruning"
  verify_release_integrity "${active_release}" ||
    die "active release failed integrity verification before pruning"
  active_sha="${active_release##*/}"
  keep["${active_sha}"]=1

  mapfile -t markers < <(
    find "${KNOWN_GOOD_DIR}" -xdev -mindepth 1 -maxdepth 1 \
      -type f -printf '%T@ %p\n' |
      sort --numeric-sort --reverse |
      cut --delimiter=' ' --fields=2-
  )

  kept_recent=0
  for marker in "${markers[@]}"; do
    sha="${marker##*/}"
    [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || continue
    [[ "${sha}" != "${active_sha}" ]] || continue
    ((kept_recent < RECENT_KNOWN_GOOD_TO_KEEP)) || break

    candidate="${RELEASES_DIR}/${sha}"
    if verify_release_integrity "${candidate}"; then
      keep["${sha}"]=1
      ((kept_recent += 1))
    else
      log "ignoring invalid known-good marker for ${sha}" >&2
      rm -f -- "${marker}" || return 1
    fi
  done

  mapfile -d '' releases < <(
    find "${RELEASES_DIR}" -xdev -mindepth 1 -maxdepth 1 \
      -type d -print0
  )

  for release_path in "${releases[@]}"; do
    sha="${release_path##*/}"
    [[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || continue
    [[ "${release_path%/*}" == "${RELEASES_DIR}" ]] || continue
    [[ -z "${keep[${sha}]+present}" ]] || continue
    [[ "${release_path}" != "${active_release}" ]] || continue

    log "pruning release ${sha}"
    rm -rf --one-file-system -- "${release_path}" || return 1
    rm -f -- "${KNOWN_GOOD_DIR}/${sha}" || return 1
  done

  log \
    "retained active release plus ${kept_recent}" \
    "recent known-good release(s)"
}

on_exit() {
  local status

  status="$1"
  trap - EXIT HUP INT TERM

  if ((status != 0 && SWITCHED == 1 && ROLLBACK_DONE == 0 &&
    DEPLOYMENT_COMPLETE == 0)); then
    rollback_current || true
  fi

  if ((status != 0 && DEPLOYMENT_COMPLETE == 0)); then
    cleanup_failed_candidate || true
  fi
  cleanup_temporary_files
  exit "${status}"
}

trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'on_exit "$?"' EXIT

main() {
  local existing_hash

  if (($# != 1)); then
    die "usage: damienwen-deploy <40-character-git-sha>"
  fi

  RELEASE_SHA="$1"
  [[ "${RELEASE_SHA}" =~ ^[0-9a-f]{40}$ ]] ||
    die "release identifier must be a full lowercase Git commit SHA"

  ((EUID == 0)) ||
    die "deployment transaction must run as root through the dispatcher"

  require_commands
  umask 0027
  acquire_deploy_lock
  validate_server_layout
  acquire_incoming_lock
  RELEASE_DIR="${RELEASES_DIR}/${RELEASE_SHA}"
  cleanup_stale_work_directories

  if [[ "$(
    systemctl show \
      --property=LoadState \
      --value \
      "${LEGACY_SERVICE_NAME}" 2> /dev/null || true
  )" == "loaded" ]]; then
    LEGACY_FALLBACK_AVAILABLE=1
  fi

  load_last_known_good
  load_or_initialize_boot_role
  reconcile_service_boot_role ||
    die "could not reconcile the persisted service boot role"
  recover_interrupted_activation

  claim_incoming_files
  if ((INCOMING_PRESENT == 1)); then
    verify_incoming_archive
    INCOMING_ARTIFACT_HASH="${ARTIFACT_HASH}"
  fi

  if verify_release_integrity "${RELEASE_DIR}"; then
    existing_hash="${ARTIFACT_HASH}"
    if ((INCOMING_PRESENT == 1)); then
      [[ "${INCOMING_ARTIFACT_HASH}" == "${existing_hash}" ]] ||
        die "an immutable release already exists with a different artifact"
    fi
    log "using existing immutable release ${RELEASE_SHA}"
  else
    [[ ! -e "${RELEASE_DIR}" && ! -L "${RELEASE_DIR}" ]] ||
      die "release directory exists but failed integrity verification"
    ((INCOMING_PRESENT == 1)) ||
      die "release ${RELEASE_SHA} is not present in incoming or releases"

    ARTIFACT_HASH="${INCOMING_ARTIFACT_HASH}"
    validate_archive_members
    extract_release
    verify_release_integrity "${RELEASE_DIR}" ||
      die "finalized release failed integrity verification"
    log "prepared immutable release ${RELEASE_SHA}"
  fi

  verify_release_integrity "${RELEASE_DIR}" ||
    die "candidate changed before preflight"
  preflight_release
  verify_release_integrity "${RELEASE_DIR}" ||
    die "candidate changed during preflight"

  mark_activation_pending "${RELEASE_SHA}" "${ACTIVATION_FALLBACK_MODE}"
  switch_current "${RELEASE_DIR}"
  log "activated release ${RELEASE_SHA}; restarting ${SERVICE_NAME}"

  if restart_production &&
    wait_for_unit_health \
      "${PRODUCTION_URL}" \
      "${PRODUCTION_HEALTH_ATTEMPTS}" \
      "${SERVICE_NAME}"; then
    if ! complete_service_migration; then
      log "could not persist the managed service boot configuration" >&2
      rollback_current || true
      return 1
    fi
    mark_release_known_good "${RELEASE_DIR}"
    DEPLOYMENT_COMPLETE=1
    clear_activation_pending
    if ! (prune_old_releases); then
      log \
        "warning: release ${RELEASE_SHA} is healthy," \
        "but retention cleanup failed" >&2
    fi
    log "release ${RELEASE_SHA} is healthy"
    return 0
  fi

  log "new release failed its production health check" >&2
  rollback_current || true
  return 1
}

main "$@"
