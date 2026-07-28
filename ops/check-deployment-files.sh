#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd -P
)"
REPO_ROOT="$(
  cd -- "${SCRIPT_DIR}/.."
  pwd -P
)"

readonly SCRIPT_DIR
readonly REPO_ROOT

cd "${REPO_ROOT}"

scripts=(
  ops/bootstrap-vps.sh
  ops/check-deployment-files.sh
  ops/deploy-release.sh
  ops/recover-activation.sh
  ops/ssh-dispatch.sh
)

for script in "${scripts[@]}"; do
  bash -n "${script}"
done

if command -v shellcheck > /dev/null; then
  shellcheck "${scripts[@]}"
else
  printf '%s\n' "shellcheck is unavailable; skipped shell lint" >&2
fi

if command -v visudo > /dev/null; then
  visudo -cf ops/damienwen-deploy.sudoers
else
  printf '%s\n' "visudo is unavailable; skipped sudoers syntax check" >&2
fi

if node -e "require.resolve('js-yaml')" > /dev/null 2>&1; then
  node <<'NODE'
const fs = require("node:fs");
const yaml = require("js-yaml");

const workflow = yaml.load(
  fs.readFileSync(".github/workflows/deploy.yml", "utf8"),
);

if (!workflow || typeof workflow !== "object" || !workflow.on || !workflow.jobs) {
  throw new Error("deploy workflow is missing required top-level keys");
}
NODE
else
  printf '%s\n' "js-yaml is unavailable; skipped workflow YAML parse" >&2
fi

grep -Fq 'output: "standalone"' next.config.ts
grep -Eq \
  'uses:[[:space:]]+actions/checkout@[0-9a-f]{40}([[:space:]]|$)' \
  .github/workflows/deploy.yml
grep -Eq \
  'uses:[[:space:]]+actions/setup-node@[0-9a-f]{40}([[:space:]]|$)' \
  .github/workflows/deploy.yml
grep -Eq \
  'uses:[[:space:]]+actions/upload-artifact@[0-9a-f]{40}([[:space:]]|$)' \
  .github/workflows/deploy.yml
grep -Eq \
  'uses:[[:space:]]+actions/download-artifact@[0-9a-f]{40}([[:space:]]|$)' \
  .github/workflows/deploy.yml
grep -Fq 'npm run verify' .github/workflows/deploy.yml
grep -Fq "vars.DEPLOY_ENABLED == 'true'" .github/workflows/deploy.yml
grep -Fq "github.event_name == 'workflow_dispatch'" \
  .github/workflows/deploy.yml
grep -Fq "DEPLOY_HOST: \${{ secrets.DEPLOY_HOST }}" \
  .github/workflows/deploy.yml
grep -Fq "DEPLOY_PORT: \${{ secrets.DEPLOY_PORT }}" \
  .github/workflows/deploy.yml
printf -v github_sha_literal '%s%s' '$' '{GITHUB_SHA}'
grep -Fq "upload-archive ${github_sha_literal}" .github/workflows/deploy.yml
grep -Fq "upload-checksum ${github_sha_literal}" .github/workflows/deploy.yml
grep -Fq "deploy ${github_sha_literal}" .github/workflows/deploy.yml
grep -Fq 'command="%s",%s %s' ops/bootstrap-vps.sh
grep -Fq 'flock --exclusive --nonblock' ops/deploy-release.sh
grep -Fq 'systemd-run' ops/deploy-release.sh
grep -Fq 'damienwen-legacy.service' ops/deploy-release.sh
grep -Fq 'readonly EXTRACT_USER="damienwen-extract"' ops/deploy-release.sh
grep -Fq "runuser --user \"\${EXTRACT_USER}\"" ops/deploy-release.sh
grep -Fq 'readonly LAST_KNOWN_GOOD_LINK=' ops/deploy-release.sh
grep -Fq 'readonly ACTIVATION_PENDING=' ops/deploy-release.sh
grep -Fq 'read_activation_pending_record' ops/deploy-release.sh
grep -Fq "mark_activation_pending \"\${RELEASE_SHA}\"" \
  ops/deploy-release.sh
grep -Eq \
  '\^\(\[0-9a-f\]\{40\}\)\[\[:space:\]\]\(legacy\|candidate\)\$' \
  ops/deploy-release.sh
grep -Fq 'readonly BOOT_ROLE_FILE=' ops/deploy-release.sh
grep -Fq 'copy_incoming_file' ops/deploy-release.sh
grep -Fq 'acquire_incoming_lock' ops/deploy-release.sh
grep -Fq "sync --file-system \"\${APP_ROOT}\"" ops/deploy-release.sh
grep -Fq "assert_regular_single_link_file \"\${ARCHIVE_PATH}\"" \
  ops/deploy-release.sh
grep -Fq 'readonly MAX_ARCHIVE_MEMBERS=10000' ops/deploy-release.sh
grep -Fq 'cleanup_stale_work_directories' ops/deploy-release.sh
grep -Fq 'kept failed release because activation-pending is unsafe' \
  ops/deploy-release.sh
grep -Fq "warning: release \${RELEASE_SHA} is healthy," \
  ops/deploy-release.sh
grep -Fq "systemctl enable \"\${LEGACY_SERVICE_NAME}\"" \
  ops/bootstrap-vps.sh
grep -Fq "systemctl disable \"\${SERVICE_NAME}\"" \
  ops/bootstrap-vps.sh
grep -Fq "systemctl is-active --quiet \"\${RECOVERY_SERVICE_NAME}\"" \
  ops/bootstrap-vps.sh
grep -Fq 'install_recovery_files' ops/bootstrap-vps.sh
grep -Fq 'persist_boot_role "legacy"' ops/bootstrap-vps.sh
grep -Fq 'InaccessiblePaths=/srv/damienwen/staging' \
  ops/damienwen.service
grep -Fq 'Requires=damienwen-recover.service' ops/damienwen.service
grep -Fq 'ExecCondition=/usr/bin/grep' ops/damienwen.service
grep -Fq 'RemainAfterExit=yes' ops/damienwen-recover.service
grep -Fq 'readonly ACTIVATION_PENDING=' ops/recover-activation.sh
grep -Fq 'read_pending_record' ops/recover-activation.sh
grep -Fq 'pending_mode' ops/recover-activation.sh
grep -Eq \
  '\^\(\[0-9a-f\]\{40\}\)\[\[:space:\]\]\(legacy\|candidate\)\$' \
  ops/recover-activation.sh
grep -Fq 'readonly BOOT_ROLE_FILE=' ops/recover-activation.sh
grep -Fq 'transition_boot_role "legacy"' ops/recover-activation.sh
grep -Fq 'Requires=damienwen-recover.service' \
  ops/damienwen-legacy-role.conf
grep -Fq 'ExecCondition=/usr/bin/grep' \
  ops/damienwen-legacy-role.conf
grep -Fq 'Requires=damienwen-recover.service' \
  ops/damienwen-managed-role.conf
grep -Fq 'ExecCondition=/usr/bin/grep' \
  ops/damienwen-managed-role.conf
grep -Fq 'readonly RECEIVE_TIMEOUT_SECONDS=120' ops/ssh-dispatch.sh
grep -Fq 'readonly MAX_INCOMING_ENTRIES=8' ops/ssh-dispatch.sh
grep -Fq 'acquire_upload_lock' ops/ssh-dispatch.sh

dispatcher_denial="$(
  SSH_ORIGINAL_COMMAND="bash" bash ops/ssh-dispatch.sh 2>&1 || true
)"
grep -Fq \
  'only upload-archive, upload-checksum, and deploy are allowed' \
  <<< "${dispatcher_denial}"
grep -Fq '"smoke:standalone": "node scripts/smoke-standalone.mjs"' package.json
grep -Fq 'npm run smoke:standalone' package.json

if command -v systemd-analyze > /dev/null &&
  command -v getent > /dev/null &&
  getent passwd damienwen > /dev/null &&
  [[ -x /usr/bin/node ]]; then
  systemd-analyze verify \
    ops/damienwen-recover.service \
    ops/damienwen.service
else
  printf '%s\n' \
    "systemd runtime prerequisites are unavailable; skipped unit verification" \
    >&2
fi

printf '%s\n' "deployment files passed available static checks"
