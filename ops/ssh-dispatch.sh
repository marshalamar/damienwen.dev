#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

readonly DEPLOY_USER="damienwen-deploy"
readonly INCOMING_DIR="/srv/damienwen/incoming"
readonly DEPLOY_SCRIPT="/usr/local/sbin/damienwen-deploy"
readonly MAX_ARCHIVE_BYTES=$((128 * 1024 * 1024))
readonly MAX_CHECKSUM_BYTES=1024
readonly MAX_INCOMING_ENTRIES=8
readonly MAX_INCOMING_TOTAL_BYTES=$((384 * 1024 * 1024))
readonly RECEIVE_TIMEOUT_SECONDS=120

TEMP_FILE=""
UPLOAD_LOCK_FD=""

die() {
  printf '[damienwen-ssh] denied: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TEMP_FILE}" &&
    "${TEMP_FILE}" == "${INCOMING_DIR}/.upload-"* &&
    -f "${TEMP_FILE}" ]]; then
    rm -f -- "${TEMP_FILE}"
  fi
}

trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
trap cleanup EXIT

validate_sha() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]] ||
    die "release identifier must be a full lowercase Git commit SHA"
}

acquire_upload_lock() {
  local orphan
  local orphan_name

  exec {UPLOAD_LOCK_FD}< "${INCOMING_DIR}"
  if ! flock --exclusive --nonblock "${UPLOAD_LOCK_FD}"; then
    die "another upload or deployment transaction is active"
  fi

  # With the stable incoming-directory inode locked, no legitimate upload can
  # still own one of these temporary names. Remove leftovers from an
  # uncatchable interruption before admitting another connection.
  shopt -s nullglob
  for orphan in "${INCOMING_DIR}"/.upload-*; do
    orphan_name="${orphan##*/}"
    [[ "${orphan_name}" =~ ^\.upload-[A-Za-z0-9]{6}$ ]] || continue
    if [[ -f "${orphan}" || -L "${orphan}" ]]; then
      rm -f -- "${orphan}"
    else
      die "incoming contains an unsafe temporary upload path"
    fi
  done
  shopt -u nullglob
}

validate_incoming_quota() {
  local entries
  local link_count
  local path
  local path_name
  local size
  local target
  local total_bytes
  local -a incoming_paths

  target="$1"
  entries=0
  total_bytes=0

  shopt -s nullglob dotglob
  incoming_paths=("${INCOMING_DIR}"/*)
  shopt -u nullglob dotglob

  for path in "${incoming_paths[@]}"; do
    # The previous value at the target is replaced atomically, so exclude it
    # from the projected persistent quota.
    [[ "${path}" != "${target}" ]] || continue
    path_name="${path##*/}"
    if [[ "${path}" != "${TEMP_FILE}" &&
      ! "${path_name}" =~ ^[0-9a-f]{40}\.tar\.gz(\.sha256)?$ ]]; then
      die "incoming contains an unexpected path"
    fi
    [[ -f "${path}" && ! -L "${path}" ]] ||
      die "incoming contains a symlink or non-regular file"
    link_count="$(stat --format='%h' -- "${path}")"
    [[ "${link_count}" == "1" ]] ||
      die "incoming contains a multiply-linked file"
    size="$(stat --format='%s' -- "${path}")"
    ((entries += 1))
    ((total_bytes += size))
  done

  ((entries <= MAX_INCOMING_ENTRIES)) ||
    die "incoming file quota is exhausted"
  ((total_bytes <= MAX_INCOMING_TOTAL_BYTES)) ||
    die "incoming byte quota is exhausted"
}

receive_file() {
  local limit
  local size
  local target

  target="$1"
  limit="$2"

  TEMP_FILE="$(mktemp "${INCOMING_DIR}/.upload-XXXXXX")"
  chmod 0600 "${TEMP_FILE}"

  if ! timeout \
    --signal=KILL \
    "${RECEIVE_TIMEOUT_SECONDS}" \
    head --bytes="$((limit + 1))" > "${TEMP_FILE}"; then
    die "upload did not finish within ${RECEIVE_TIMEOUT_SECONDS} seconds"
  fi
  size="$(stat --format='%s' "${TEMP_FILE}")"
  ((size > 0)) || die "empty upload"
  ((size <= limit)) || die "upload exceeds the allowed size"
  validate_incoming_quota "${target}"

  mv --no-target-directory --force -- "${TEMP_FILE}" "${target}"
  TEMP_FILE=""
}

main() {
  local actual_user
  local command
  local operation
  local release_sha

  command="${SSH_ORIGINAL_COMMAND-}"
  if [[ ! "${command}" =~ ^(upload-archive|upload-checksum|deploy)[[:space:]]+([0-9a-f]{40})$ ]]; then
    die "only upload-archive, upload-checksum, and deploy are allowed"
  fi

  operation="${BASH_REMATCH[1]}"
  release_sha="${BASH_REMATCH[2]}"
  validate_sha "${release_sha}"

  actual_user="$(id -un)"
  [[ "${actual_user}" == "${DEPLOY_USER}" ]] ||
    die "dispatcher must run as ${DEPLOY_USER}"

  umask 0077

  case "${operation}" in
    upload-archive)
      acquire_upload_lock
      receive_file \
        "${INCOMING_DIR}/${release_sha}.tar.gz" \
        "${MAX_ARCHIVE_BYTES}"
      ;;
    upload-checksum)
      acquire_upload_lock
      receive_file \
        "${INCOMING_DIR}/${release_sha}.tar.gz.sha256" \
        "${MAX_CHECKSUM_BYTES}"
      ;;
    deploy)
      exec sudo --non-interactive "${DEPLOY_SCRIPT}" "${release_sha}"
      ;;
    *)
      die "unreachable operation"
      ;;
  esac
}

main "$@"
