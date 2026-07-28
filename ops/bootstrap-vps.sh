#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

readonly APP_USER="damienwen"
readonly APP_GROUP="damienwen"
readonly EXTRACT_USER="damienwen-extract"
readonly EXTRACT_GROUP="damienwen-extract"
readonly DEPLOY_USER="damienwen-deploy"
readonly DEPLOY_GROUP="damienwen-deploy"
readonly APP_ROOT="/srv/damienwen"
readonly LAST_KNOWN_GOOD_LINK="${APP_ROOT}/last-known-good"
readonly BOOT_ROLE_FILE="${APP_ROOT}/boot-role"
readonly SERVICE_NAME="damienwen.service"
readonly SERVICE_TARGET="/etc/systemd/system/${SERVICE_NAME}"
readonly MANAGED_ROLE_DROPIN_DIR="/etc/systemd/system/${SERVICE_NAME}.d"
readonly MANAGED_ROLE_DROPIN_TARGET="${MANAGED_ROLE_DROPIN_DIR}/boot-role.conf"
readonly LEGACY_SERVICE_NAME="damienwen-legacy.service"
readonly LEGACY_SERVICE_TARGET="/etc/systemd/system/${LEGACY_SERVICE_NAME}"
readonly LEGACY_ROLE_DROPIN_DIR="/etc/systemd/system/${LEGACY_SERVICE_NAME}.d"
readonly LEGACY_ROLE_DROPIN_TARGET="${LEGACY_ROLE_DROPIN_DIR}/boot-role.conf"
readonly RECOVERY_SERVICE_NAME="damienwen-recover.service"
readonly RECOVERY_SERVICE_TARGET="/etc/systemd/system/${RECOVERY_SERVICE_NAME}"
readonly DEPLOY_SCRIPT_TARGET="/usr/local/sbin/damienwen-deploy"
readonly DISPATCH_SCRIPT_TARGET="/usr/local/sbin/damienwen-ssh-dispatch"
readonly RECOVERY_SCRIPT_TARGET="/usr/local/sbin/damienwen-recover"
readonly SUDOERS_TARGET="/etc/sudoers.d/damienwen-deploy"
readonly MINIMUM_NODE_VERSION="22.13.0"
readonly EXPECTED_ARCHITECTURE="x86_64"

SCRIPT_DIR=""
AUTHORIZED_KEY_FILE=""
REPLACE_EXISTING=0
TEMP_AUTHORIZED_KEYS=""
NEXT_BOOT_ROLE_FILE=""
BACKUP_TIMESTAMP=""

log() {
  printf '[bootstrap-vps] %s\n' "$*"
}

die() {
  printf '[bootstrap-vps] error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  sudo bash ops/bootstrap-vps.sh \
    --authorized-key /absolute/path/to/damienwen-actions.pub \
    [--replace-existing]

The public key must be an ssh-ed25519 key. It is installed with a forced
command that only accepts release uploads and deploy <sha>. --replace-existing
is required before this script replaces a different managed file. Existing
managed files are backed up first.
EOF
}

cleanup() {
  if [[ -n "${TEMP_AUTHORIZED_KEYS}" &&
    "${TEMP_AUTHORIZED_KEYS}" == /tmp/damienwen-authorized-keys.* &&
    -f "${TEMP_AUTHORIZED_KEYS}" ]]; then
    rm -f -- "${TEMP_AUTHORIZED_KEYS}"
  fi
  if [[ -n "${NEXT_BOOT_ROLE_FILE}" &&
    "${NEXT_BOOT_ROLE_FILE}" == "${APP_ROOT}/.boot-role-"* &&
    -f "${NEXT_BOOT_ROLE_FILE}" &&
    ! -L "${NEXT_BOOT_ROLE_FILE}" ]]; then
    rm -f -- "${NEXT_BOOT_ROLE_FILE}"
  fi
}

trap cleanup EXIT

require_command() {
  local command_name

  command_name="$1"
  command -v "${command_name}" > /dev/null ||
    die "required command is unavailable: ${command_name}"
}

version_is_supported() {
  /usr/bin/node -e '
    const current = process.versions.node.split(".").map(Number);
    const minimum = process.argv[1].split(".").map(Number);
    if (current[0] !== minimum[0]) process.exit(1);
    for (let index = 0; index < 3; index += 1) {
      if (current[index] > minimum[index]) process.exit(0);
      if (current[index] < minimum[index]) process.exit(1);
    }
    process.exit(0);
  ' "${MINIMUM_NODE_VERSION}"
}

assert_replace_allowed() {
  local source
  local target

  source="$1"
  target="$2"

  if [[ -e "${target}" ]] && ! cmp --silent -- "${source}" "${target}"; then
    ((REPLACE_EXISTING == 1)) ||
      die "${target} differs; inspect it and rerun with --replace-existing"
  fi
}

backup_if_different() {
  local source
  local target

  source="$1"
  target="$2"

  if [[ -e "${target}" ]] && ! cmp --silent -- "${source}" "${target}"; then
    cp --archive -- "${target}" "${target}.backup-${BACKUP_TIMESTAMP}"
    log "backed up ${target}"
  fi
}

parse_arguments() {
  while (($# > 0)); do
    case "$1" in
      --authorized-key)
        (($# >= 2)) || die "--authorized-key requires a path"
        AUTHORIZED_KEY_FILE="$2"
        shift 2
        ;;
      --replace-existing)
        REPLACE_EXISTING=1
        shift
        ;;
      --help | -h)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  [[ -n "${AUTHORIZED_KEY_FILE}" ]] ||
    die "--authorized-key is required"
  [[ "${AUTHORIZED_KEY_FILE}" == /* ]] ||
    die "--authorized-key must use an absolute path"
  [[ -f "${AUTHORIZED_KEY_FILE}" ]] ||
    die "public key file does not exist: ${AUTHORIZED_KEY_FILE}"
}

validate_public_key() {
  local key_lines
  local public_key

  mapfile -t key_lines < "${AUTHORIZED_KEY_FILE}"
  ((${#key_lines[@]} == 1)) ||
    die "public key file must contain exactly one line"

  public_key="${key_lines[0]}"
  if [[ ! "${public_key}" =~ ^ssh-ed25519[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
    die "public key must be a valid ssh-ed25519 public key"
  fi
  ssh-keygen -l -f "${AUTHORIZED_KEY_FILE}" > /dev/null ||
    die "ssh-keygen could not parse the public key"

  TEMP_AUTHORIZED_KEYS="$(mktemp /tmp/damienwen-authorized-keys.XXXXXX)"
  printf 'command="%s",%s %s\n' \
    "${DISPATCH_SCRIPT_TARGET}" \
    'no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc,no-pty' \
    "${public_key}" > "${TEMP_AUTHORIZED_KEYS}"
  chmod 600 "${TEMP_AUTHORIZED_KEYS}"
}

create_accounts() {
  if ! getent group "${APP_GROUP}" > /dev/null; then
    groupadd --system "${APP_GROUP}"
    log "created application group ${APP_GROUP}"
  fi

  if ! id "${APP_USER}" > /dev/null 2>&1; then
    useradd \
      --system \
      --gid "${APP_GROUP}" \
      --home-dir "${APP_ROOT}" \
      --no-create-home \
      --shell /usr/sbin/nologin \
      "${APP_USER}"
    log "created application user ${APP_USER}"
  fi

  if ! getent group "${EXTRACT_GROUP}" > /dev/null; then
    groupadd --system "${EXTRACT_GROUP}"
    log "created extraction group ${EXTRACT_GROUP}"
  fi

  if ! id "${EXTRACT_USER}" > /dev/null 2>&1; then
    useradd \
      --system \
      --gid "${EXTRACT_GROUP}" \
      --home-dir "${APP_ROOT}" \
      --no-create-home \
      --shell /usr/sbin/nologin \
      "${EXTRACT_USER}"
    log "created extraction user ${EXTRACT_USER}"
  fi
  [[ "$(id --group --name "${EXTRACT_USER}")" == "${EXTRACT_GROUP}" ]] ||
    die "${EXTRACT_USER} must use ${EXTRACT_GROUP} as its primary group"
  [[ "$(id --user "${EXTRACT_USER}")" != "$(id --user "${APP_USER}")" ]] ||
    die "${EXTRACT_USER} and ${APP_USER} must use different user IDs"

  if ! getent group "${DEPLOY_GROUP}" > /dev/null; then
    groupadd "${DEPLOY_GROUP}"
  fi

  if ! id "${DEPLOY_USER}" > /dev/null 2>&1; then
    useradd \
      --create-home \
      --gid "${DEPLOY_GROUP}" \
      --shell /bin/bash \
      "${DEPLOY_USER}"
    log "created deployment user ${DEPLOY_USER}"
  fi

  gpasswd --delete "${DEPLOY_USER}" "${APP_GROUP}" > /dev/null 2>&1 || true
  gpasswd --delete "${EXTRACT_USER}" "${APP_GROUP}" > /dev/null 2>&1 || true
  gpasswd --delete "${APP_USER}" "${EXTRACT_GROUP}" > /dev/null 2>&1 || true
  gpasswd --delete "${DEPLOY_USER}" "${EXTRACT_GROUP}" > /dev/null 2>&1 || true
  passwd --lock "${EXTRACT_USER}" > /dev/null
  passwd --lock "${DEPLOY_USER}" > /dev/null
}

install_authorized_key() {
  local deploy_entry
  local deploy_home
  local target

  deploy_entry="$(getent passwd "${DEPLOY_USER}")"
  deploy_home="${deploy_entry%:*}"
  deploy_home="${deploy_home##*:}"

  [[ -n "${deploy_home}" && "${deploy_home}" == /* &&
    "${deploy_home}" != "/" ]] ||
    die "deployment user has an unsafe home directory"

  target="${deploy_home}/.ssh/authorized_keys"
  if [[ -L "${deploy_home}/.ssh" ]] ||
    [[ -e "${deploy_home}/.ssh" && ! -d "${deploy_home}/.ssh" ]]; then
    die "${deploy_home}/.ssh must be a real directory"
  fi
  if [[ -L "${target}" ]] ||
    [[ -e "${target}" && ! -f "${target}" ]]; then
    die "${target} must be a regular file"
  fi
  if [[ -f "${target}" &&
    "$(stat --format='%h' -- "${target}")" != "1" ]]; then
    die "${target} must not have multiple hard links"
  fi
  if [[ -e "${target}" ]] &&
    ! cmp --silent -- "${TEMP_AUTHORIZED_KEYS}" "${target}"; then
    ((REPLACE_EXISTING == 1)) ||
      die "${target} differs; rerun with --replace-existing to rotate it"
    cp --archive -- "${target}" "${target}.backup-${BACKUP_TIMESTAMP}"
  fi

  chown root:"${DEPLOY_GROUP}" "${deploy_home}"
  chmod 0750 "${deploy_home}"
  install \
    --directory \
    --owner root \
    --group root \
    --mode 0700 \
    "${deploy_home}/.ssh"
  install \
    --owner root \
    --group root \
    --mode 0600 \
    "${TEMP_AUTHORIZED_KEYS}" \
    "${target}"
}

install_app_directories() {
  install \
    --directory \
    --owner root \
    --group root \
    --mode 0755 \
    "${APP_ROOT}"
  install \
    --directory \
    --owner "${DEPLOY_USER}" \
    --group "${DEPLOY_GROUP}" \
    --mode 0700 \
    "${APP_ROOT}/incoming"
  install \
    --directory \
    --owner root \
    --group "${APP_GROUP}" \
    --mode 0750 \
    "${APP_ROOT}/releases"
  install \
    --directory \
    --owner root \
    --group "${EXTRACT_GROUP}" \
    --mode 0710 \
    "${APP_ROOT}/staging"
  install \
    --directory \
    --owner root \
    --group root \
    --mode 0700 \
    "${APP_ROOT}/transactions" \
    "${APP_ROOT}/known-good"
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
  if [[ -e "${BOOT_ROLE_FILE}" || -L "${BOOT_ROLE_FILE}" ]]; then
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

prepare_legacy_fallback() {
  local drop_in_paths
  local fragment_path
  local legacy_source

  if [[ -f "${LEGACY_SERVICE_TARGET}" ]]; then
    systemd-analyze verify "${LEGACY_SERVICE_TARGET}"
    log "preserving existing ${LEGACY_SERVICE_NAME}"
    return 0
  fi

  if [[ -L "${LAST_KNOWN_GOOD_LINK}" ]]; then
    log "managed last-known-good exists; no legacy service migration is needed"
    return 0
  fi

  legacy_source="${SERVICE_TARGET}"
  if [[ ! -f "${legacy_source}" ]]; then
    fragment_path="$(
      systemctl show \
        --property=FragmentPath \
        --value \
        "${SERVICE_NAME}" 2> /dev/null || true
    )"
    [[ -n "${fragment_path}" && -f "${fragment_path}" ]] || return 0
    legacy_source="${fragment_path}"
  fi

  cmp --silent -- "${SCRIPT_DIR}/damienwen.service" "${legacy_source}" &&
    return 0
  ((REPLACE_EXISTING == 1)) ||
    die "existing active service differs; rerun with --replace-existing"

  systemctl is-active --quiet "${SERVICE_NAME}" ||
    die "existing ${SERVICE_NAME} is not active; refusing migration without a known-good fallback"
  curl --fail --silent --max-time 3 "http://127.0.0.1:3000/" > /dev/null ||
    die "existing ${SERVICE_NAME} is not healthy on 127.0.0.1:3000"

  drop_in_paths="$(
    systemctl show \
      --property=DropInPaths \
      --value \
      "${SERVICE_NAME}"
  )"
  [[ -z "${drop_in_paths}" ]] ||
    die "existing service has drop-ins; create and verify a legacy fallback unit manually"

  if grep -Eq '%[A-Za-z]' "${legacy_source}"; then
    die "existing service uses unit specifiers; create a legacy fallback unit manually"
  fi
  if grep -Fq "${APP_ROOT}/current" "${legacy_source}"; then
    die "existing service depends on the managed current link; create a legacy fallback manually"
  fi

  install \
    --owner root \
    --group root \
    --mode 0644 \
    "${legacy_source}" \
    "${LEGACY_SERVICE_TARGET}"

  if ! systemd-analyze verify "${LEGACY_SERVICE_TARGET}"; then
    rm -f -- "${LEGACY_SERVICE_TARGET}"
    die "preserved legacy unit failed systemd verification"
  fi

  log "preserved active legacy unit as ${LEGACY_SERVICE_NAME}"
}

arm_legacy_boot_fallback() {
  if [[ -L "${LAST_KNOWN_GOOD_LINK}" ||
    ! -f "${LEGACY_SERVICE_TARGET}" ]]; then
    return 0
  fi

  # Do this before replacing damienwen.service. If bootstrap is interrupted
  # after this point, the copied old unit—not a half-installed managed unit—is
  # selected for the next boot. The currently running process is not stopped.
  systemctl daemon-reload
  systemctl enable "${LEGACY_SERVICE_NAME}" > /dev/null
  persist_boot_role "legacy"
  systemctl disable "${SERVICE_NAME}" > /dev/null
  log "armed ${LEGACY_SERVICE_NAME} before replacing the managed unit"
}

configure_service_boot_state() {
  local last_known_good_target

  if [[ -L "${LAST_KNOWN_GOOD_LINK}" ]]; then
    last_known_good_target="$(
      readlink --canonicalize "${LAST_KNOWN_GOOD_LINK}"
    )" || die "last-known-good link is broken"
    [[ "${last_known_good_target}" == "${APP_ROOT}/releases/"* ]] ||
      die "last-known-good link points outside managed releases"

    systemctl enable "${SERVICE_NAME}" > /dev/null
    persist_boot_role "managed"
    if [[ -f "${LEGACY_SERVICE_TARGET}" ]]; then
      systemctl disable "${LEGACY_SERVICE_NAME}" > /dev/null
    fi
    log "managed service remains enabled from the recorded known-good release"
    return 0
  fi

  [[ ! -e "${LAST_KNOWN_GOOD_LINK}" ]] ||
    die "last-known-good path exists but is not a symbolic link"

  if [[ -f "${LEGACY_SERVICE_TARGET}" ]]; then
    systemctl enable "${LEGACY_SERVICE_NAME}" > /dev/null
    persist_boot_role "legacy"
    systemctl disable "${SERVICE_NAME}" > /dev/null
    log \
      "enabled ${LEGACY_SERVICE_NAME} for reboot safety until the first" \
      "managed release succeeds"
    return 0
  fi

  systemctl enable "${SERVICE_NAME}" > /dev/null
  persist_boot_role "managed"
}

install_recovery_files() {
  backup_if_different \
    "${SCRIPT_DIR}/recover-activation.sh" \
    "${RECOVERY_SCRIPT_TARGET}"
  backup_if_different \
    "${SCRIPT_DIR}/damienwen-recover.service" \
    "${RECOVERY_SERVICE_TARGET}"
  backup_if_different \
    "${SCRIPT_DIR}/damienwen-managed-role.conf" \
    "${MANAGED_ROLE_DROPIN_TARGET}"
  if [[ -f "${LEGACY_SERVICE_TARGET}" ]]; then
    backup_if_different \
      "${SCRIPT_DIR}/damienwen-legacy-role.conf" \
      "${LEGACY_ROLE_DROPIN_TARGET}"
  fi

  install \
    --owner root \
    --group root \
    --mode 0755 \
    "${SCRIPT_DIR}/recover-activation.sh" \
    "${RECOVERY_SCRIPT_TARGET}"
  install \
    --owner root \
    --group root \
    --mode 0644 \
    "${SCRIPT_DIR}/damienwen-recover.service" \
    "${RECOVERY_SERVICE_TARGET}"
  install \
    --directory \
    --owner root \
    --group root \
    --mode 0755 \
    "${MANAGED_ROLE_DROPIN_DIR}"
  install \
    --owner root \
    --group root \
    --mode 0644 \
    "${SCRIPT_DIR}/damienwen-managed-role.conf" \
    "${MANAGED_ROLE_DROPIN_TARGET}"
  if [[ -f "${LEGACY_SERVICE_TARGET}" ]]; then
    install \
      --directory \
      --owner root \
      --group root \
      --mode 0755 \
      "${LEGACY_ROLE_DROPIN_DIR}"
    install \
      --owner root \
      --group root \
      --mode 0644 \
      "${SCRIPT_DIR}/damienwen-legacy-role.conf" \
      "${LEGACY_ROLE_DROPIN_TARGET}"
  fi

  systemctl daemon-reload
  systemd-analyze verify "${RECOVERY_SERVICE_TARGET}"
  if [[ -f "${LEGACY_SERVICE_TARGET}" ]]; then
    systemd-analyze verify "${LEGACY_SERVICE_TARGET}"
  fi
  systemctl enable "${RECOVERY_SERVICE_NAME}" > /dev/null
}

install_managed_files() {
  backup_if_different \
    "${SCRIPT_DIR}/deploy-release.sh" \
    "${DEPLOY_SCRIPT_TARGET}"
  backup_if_different \
    "${SCRIPT_DIR}/ssh-dispatch.sh" \
    "${DISPATCH_SCRIPT_TARGET}"
  backup_if_different \
    "${SCRIPT_DIR}/damienwen.service" \
    "${SERVICE_TARGET}"
  backup_if_different \
    "${SCRIPT_DIR}/damienwen-deploy.sudoers" \
    "${SUDOERS_TARGET}"

  install \
    --owner root \
    --group root \
    --mode 0755 \
    "${SCRIPT_DIR}/deploy-release.sh" \
    "${DEPLOY_SCRIPT_TARGET}"
  install \
    --owner root \
    --group root \
    --mode 0755 \
    "${SCRIPT_DIR}/ssh-dispatch.sh" \
    "${DISPATCH_SCRIPT_TARGET}"
  install \
    --owner root \
    --group root \
    --mode 0440 \
    "${SCRIPT_DIR}/damienwen-deploy.sudoers" \
    "${SUDOERS_TARGET}"

  visudo --check --file "${SUDOERS_TARGET}"

  # The recovery unit was installed and enabled before any boot-role change.
  install \
    --owner root \
    --group root \
    --mode 0644 \
    "${SCRIPT_DIR}/damienwen.service" \
    "${SERVICE_TARGET}"

  systemctl daemon-reload
  systemd-analyze verify "${SERVICE_TARGET}" "${RECOVERY_SERVICE_TARGET}"
  configure_service_boot_state
  if systemctl is-active --quiet "${RECOVERY_SERVICE_NAME}"; then
    "${RECOVERY_SCRIPT_TARGET}"
  else
    systemctl start "${RECOVERY_SERVICE_NAME}"
  fi
}

main() {
  local architecture
  local command_name
  local node_version

  parse_arguments "$@"

  if ((EUID != 0)); then
    die "run this one-time bootstrap as root via sudo"
  fi

  SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
    pwd -P
  )"
  BACKUP_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

  for command_name in \
    bash chmod chown cmp cp curl cut date dirname find flock getent gpasswd \
    grep groupadd head id install journalctl ln mapfile mkdir mktemp mv passwd \
    readlink rm runuser sha256sum sleep sort ssh-keygen stat sudo sync \
    systemctl systemd-analyze systemd-run tar timeout touch uname useradd \
    visudo xargs; do
    require_command "${command_name}"
  done

  architecture="$(uname --machine)"
  [[ "${architecture}" == "${EXPECTED_ARCHITECTURE}" ]] ||
    die "Actions artifacts require ${EXPECTED_ARCHITECTURE}, found ${architecture}"

  [[ -x /usr/bin/node ]] ||
    die "install a system-wide Node.js executable at /usr/bin/node"
  version_is_supported ||
    die "Node.js 22.x at ${MINIMUM_NODE_VERSION} or newer is required"
  node_version="$(/usr/bin/node --version)"

  bash -n "${SCRIPT_DIR}/deploy-release.sh"
  bash -n "${SCRIPT_DIR}/recover-activation.sh"
  bash -n "${SCRIPT_DIR}/ssh-dispatch.sh"
  visudo --check --file "${SCRIPT_DIR}/damienwen-deploy.sudoers"

  assert_replace_allowed \
    "${SCRIPT_DIR}/deploy-release.sh" \
    "${DEPLOY_SCRIPT_TARGET}"
  assert_replace_allowed \
    "${SCRIPT_DIR}/ssh-dispatch.sh" \
    "${DISPATCH_SCRIPT_TARGET}"
  assert_replace_allowed \
    "${SCRIPT_DIR}/recover-activation.sh" \
    "${RECOVERY_SCRIPT_TARGET}"
  assert_replace_allowed \
    "${SCRIPT_DIR}/damienwen-recover.service" \
    "${RECOVERY_SERVICE_TARGET}"
  assert_replace_allowed \
    "${SCRIPT_DIR}/damienwen-managed-role.conf" \
    "${MANAGED_ROLE_DROPIN_TARGET}"
  assert_replace_allowed \
    "${SCRIPT_DIR}/damienwen-legacy-role.conf" \
    "${LEGACY_ROLE_DROPIN_TARGET}"
  assert_replace_allowed \
    "${SCRIPT_DIR}/damienwen.service" \
    "${SERVICE_TARGET}"
  assert_replace_allowed \
    "${SCRIPT_DIR}/damienwen-deploy.sudoers" \
    "${SUDOERS_TARGET}"

  validate_public_key
  create_accounts
  install_app_directories
  prepare_legacy_fallback
  install_recovery_files
  arm_legacy_boot_fallback
  install_authorized_key

  install_managed_files

  log "bootstrap complete with Node.js ${node_version}"
  log "the current website process was not stopped or restarted"
  log "the first successful GitHub Actions deployment will start ${SERVICE_NAME}"
}

main "$@"
