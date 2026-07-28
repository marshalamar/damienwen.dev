# VPS deployment

Production deploys are verified, immutable standalone releases:

```text
push main
  -> secret-free build job: npm ci + npm run verify
  -> reproducibly package dist/standalone and calculate SHA-256
manual workflow_dispatch from reviewed main
  -> fresh deploy job verifies the tested workflow artifact
  -> forced SSH command uploads archive and checksum
  -> root deployment transaction takes an exclusive flock
  -> copy each upload into a bounded root-private inode
  -> validate archive type, member count, and logical size
  -> extract as the isolated damienwen-extract user
  -> finalize as root-owned, read-only release
  -> verify the complete release-tree hash
  -> preflight on http://127.0.0.1:3100/
  -> persist an activation-pending marker
  -> atomically switch /srv/damienwen/current
  -> restart damienwen.service on 127.0.0.1:3000
  -> restore the previous standalone or preserved legacy service on failure
```

`cloudflared`, its Tunnel token, DNS, and ports 443/80 are not changed. The
Tunnel's origin remains `http://127.0.0.1:3000`.

## Security model

- Verification and packaging run in a build job with no production
  environment. A fresh deploy job downloads only the tested artifact and does
  not check out the repository or execute npm lifecycle scripts.
- `damienwen` runs Node and has no login shell.
- `damienwen-extract` is a separate no-login account used only by the root
  deployment transaction to run `tar`.
- `damienwen-deploy` owns only `/srv/damienwen/incoming`.
- The deployment user's home, `.ssh`, and forced `authorized_keys` file are
  root-owned, so the restricted account cannot replace its forced command.
- The Actions public key has a forced command. It cannot request a shell,
  forwarding, a PTY, or arbitrary commands.
- The root-owned dispatcher accepts exactly:
  `upload-archive <40-sha>`, `upload-checksum <40-sha>`, and
  `deploy <40-sha>`.
- Upload admission is serialized on the incoming-directory inode. A receive
  must finish within 120 seconds; persistent incoming state is capped at eight
  files and 384 MiB. Orphaned temporary uploads are removed before the next
  admitted upload.
- Each upload is size-limited, written to a temporary file, and atomically
  renamed to a fixed SHA-derived filename.
- The only passwordless sudo command runs the root-owned deployment script;
  that script accepts one validated lowercase 40-character Git SHA.
- The deployment script reads each upload as `damienwen-deploy` into a new,
  bounded, root-private transaction inode. An upload writer retaining an old
  file descriptor therefore cannot change the bytes root later verifies.
- Transaction files are then rejected if they are symlinks, non-regular files,
  or files with multiple hard links.
- Archives are limited to 10,000 members, 64 MiB per regular file, and 512 MiB
  total logical file data. Links and special archive members are rejected.
- The archive is streamed over stdin to `tar` running as
  `damienwen-extract`. Its staging parent cannot be traversed by the runtime
  account. Root revokes extractor access before validating and finalizing the
  tree.
- Final releases are `root:damienwen`, with no group/other write bit. The
  deploy account cannot alter a finalized release or the `current` link.
- Every release stores a deterministic hash of all file paths and contents.
  Ownership, writable bits, file types, and this hash are checked before
  preflight, activation, and rollback.
- `flock` prevents concurrent server-side deployment transactions.
- Stale partial uploads, staging directories, root-only transactions, and
  unretained failed releases left by an uncatchable interruption are removed
  after 24 hours by a later locked deployment.

No root password, GitHub token, Cloudflare token, or private SSH key is stored
on the VPS.

## First-migration safety

When bootstrap replaces a different, currently active and healthy
`damienwen.service`, it copies the exact old unit to the fixed inactive unit
`damienwen-legacy.service`. It does not stop the running site. Until a managed
release has passed production health checks, bootstrap enables the legacy unit
for the next reboot and leaves the managed unit disabled. The already-running
process is not restarted while bootstrap makes this boot-state change.

Both website units depend on `damienwen-recover.service` and have a root-owned
`ExecCondition` that reads `/srv/damienwen/boot-role`. A role transition first
enables the destination unit, then durably records the new role, then disables
the source unit. If power fails while both unit names are enabled, only the
unit selected by the persisted role can start.

Automatic preservation deliberately refuses units that:

- are inactive or fail the existing `127.0.0.1:3000` health check;
- have systemd drop-ins;
- use systemd unit specifiers such as `%n`; or
- depend on `/srv/damienwen/current`.

Those cases need a manually reviewed legacy unit before migration. This is
safer than guessing how an arbitrary unit and its drop-ins should be merged.

Every candidate starts first as the application user in a transient systemd
unit on `127.0.0.1:3100`. Until two consecutive HTTP checks pass, neither the
`current` link nor the production service is touched. Thus a failed first
preflight leaves the original process serving port 3000.

After preflight succeeds, the deployment first persists
`/srv/damienwen/activation-pending`. The root-only record contains both the
candidate SHA and its durable fallback phase: `legacy` while the preserved
service is still usable, or `candidate` after that service has failed. The
deployment then stops an active legacy fallback, switches `current`, selects
the managed role, and starts the new service on port 3000. If power fails
before production is confirmed, boot recovery reads that record and selects
the last-known-good release, the preserved legacy role, or the exact verified
candidate before either website unit starts. If production activation fails
normally and there is no earlier standalone release, the script selects,
starts, and health-checks the preserved legacy unit before removing the new
link. If the legacy unit also fails, the script durably changes the record to
`candidate` before retrying that same verified candidate. A successful retry
becomes the new rollback baseline.

Only after the managed service passes two consecutive production checks does
the transaction enable it for future boots, disable the legacy unit,
atomically update `/srv/damienwen/last-known-good`, and clear the pending
marker. File-system sync points preserve that ordering across power loss.

The enabled `damienwen-recover.service` runs once before either website unit on
every boot. If an activation was interrupted, it restores the persistent
last-known-good release. During a first migration it leaves the enabled legacy
unit in charge; on a completely fresh VPS with no fallback, it retains only
the already verified and preflighted candidate. A later deployment performs
the same recovery check before accepting another upload.

On a completely fresh VPS there is no legacy service to preserve. If its first
candidate passes preflight but unexpectedly fails only after switching to port
3000, the verified candidate remains selected so systemd can retry it. This
case is reported as a failed deployment and requires console inspection.

## Retention

A release becomes known-good only after the production service passes two
consecutive HTTP checks. After a successful deployment, pruning keeps:

- the active release; and
- the four most recent other known-good releases, or all of them if fewer
  than four exist.

Invalid, failed, and older releases are removed only after a new production
release succeeds. The active path is resolved and checked again before any
pruning. Retention cleanup is best-effort: a cleanup failure is logged as a
warning and does not turn an otherwise healthy production activation into a
failed deployment.

## One-time VPS bootstrap

Prerequisites on Ubuntu:

- Ubuntu 22.04 or newer on `x86_64`;
- system-wide Node.js `22.x` at `>=22.13.0`, installed at `/usr/bin/node`;
- standard Ubuntu `sudo`, systemd, `curl`, GNU tar/coreutils, and util-linux;
- the checked-out or copied `ops/` directory.

Create a dedicated key pair on a trusted workstation. Do not add a passphrase
because Actions cannot answer an interactive prompt:

```bash
ssh-keygen \
  -t ed25519 \
  -f ./damienwen-actions \
  -C "github-actions damienwen.dev"
```

Copy only `damienwen-actions.pub` through the existing trusted SSH session:

```bash
sudo bash ops/bootstrap-vps.sh \
  --authorized-key /absolute/path/to/damienwen-actions.pub
```

An existing different unit or managed file is never silently replaced. Inspect
the supplied files, then explicitly allow backup and replacement:

```bash
sudo bash ops/bootstrap-vps.sh \
  --authorized-key /absolute/path/to/damienwen-actions.pub \
  --replace-existing
```

Different managed files receive UTC-timestamped backups. During a migration,
bootstrap installs and enables the one-shot recovery unit and legacy
role-check drop-in before changing the persisted boot role or replacing the
old unit. It starts recovery only after the managed unit and role are complete.
The current website is not stopped or restarted.

## GitHub production environment

Create an environment named `production` and restrict its deployment branch to
`main`. Add at least one trusted reviewer who is not the person or automation
that pushes releases, enable “Prevent self-review,” and disallow administrator
bypass. Keep `.github/CODEOWNERS`, and protect `main` with a ruleset that
requires an approving code-owner review for changes to `.github/workflows/`
and `ops/`. Do not store production secrets until those controls are active.

Then configure:

| Type | Name | Value |
| --- | --- | --- |
| Secret | `DEPLOY_HOST` | VPS hostname or IPv4 address |
| Secret | `DEPLOY_PORT` | SSH port, such as `22` |
| Secret | `DEPLOY_SSH_KEY` | Complete contents of `damienwen-actions` |
| Secret | `DEPLOY_KNOWN_HOSTS` | Verified OpenSSH known-hosts line |

Keep the repository variable `DEPLOY_ENABLED` absent or set to `false` while
bootstrapping. After the reviewer protection, key, known-hosts entry, secrets,
and VPS bootstrap have all been verified, set that repository variable to
exactly `true`. Pushes to `main` only build and verify. A production deployment
also requires an explicit dispatch from reviewed `main`:

```bash
gh workflow run deploy.yml --ref main
```

The deploy job then waits for the protected-environment approval. It never
loads production secrets merely because a commit was pushed.

Do not generate `DEPLOY_KNOWN_HOSTS` blindly inside Actions. Obtain the host
key with `ssh-keyscan`, then compare its fingerprint with
`/etc/ssh/ssh_host_ed25519_key.pub` through the provider console or an already
trusted SSH connection. For a custom port the known-hosts hostname is normally
`[host]:port`.

## Operations

Inspect production and the preserved fallback:

```bash
sudo systemctl status damienwen.service
sudo systemctl status damienwen-legacy.service
sudo systemctl status damienwen-recover.service
sudo journalctl -u damienwen.service -n 100 --no-pager
sudo journalctl -u damienwen-recover.service -n 50 --no-pager
curl --fail http://127.0.0.1:3000/
```

Reactivate a retained release through the same validated transaction:

```bash
sudo /usr/local/sbin/damienwen-deploy <40-character-git-sha>
```

Run repository-side checks:

```bash
bash ops/check-deployment-files.sh
```

The site artifact does not replace root-owned operational files. After a
reviewed change to the dispatcher, deployment script, unit, or sudoers, rerun
bootstrap with `--replace-existing`.
