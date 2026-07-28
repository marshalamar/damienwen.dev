# Operations reference

## Content model

- Essays: `content/essays/<number>-<slug>.mdx`
- Images: `public/essays/<slug>/`
- Article metadata: title and publication date are required; subtitle, excerpt,
  and source URL are optional.
- Filename supplies the stable public slug and display number.
- `npm run essay:new -- <slug> "<title>"` allocates the next number and uses
  the current date in `Asia/Shanghai`.
- `npm run verify` is the required local quality gate.

## Production path

```text
browser
  -> Cloudflare
  -> Cloudflare Tunnel
  -> http://127.0.0.1:3000
  -> damienwen.service
  -> /srv/damienwen/current/server.js
```

The Cloudflare Tunnel configuration is independent from article deployment.
Never route this site through the VPS public port `443`.

## GitHub Actions contract

The production workflow lives at `.github/workflows/deploy.yml`. It must:

1. use a secret-free build job to install locked dependencies and run
   `npm run verify`, including type checking, standalone checks, and article
   image checks;
2. package `dist/standalone` reproducibly, calculate its SHA-256, and pass the
   tested files through a workflow artifact;
3. run deployment on a fresh runner that does not check out the repository or
   execute package scripts, and verify the downloaded artifact before loading
   production credentials;
4. use the forced SSH dispatcher to upload only the archive and checksum;
5. serialize upload admission, enforce its receive timeout and aggregate
   incoming quota, then take the VPS deployment lock and copy each upload into
   a bounded root-private inode;
6. extract as the dedicated no-login `damienwen-extract` user under
   `/srv/damienwen/staging`, which the long-running `damienwen` user cannot
   access;
7. finalize a root-owned read-only release and verify its complete tree hash;
8. preflight it through a transient service on `127.0.0.1:3100`;
9. persist the candidate SHA and durable fallback phase in
   `/srv/damienwen/activation-pending`, atomically switch
   `/srv/damienwen/current`, and restart only `damienwen.service`;
10. check `http://127.0.0.1:3000` twice;
11. update `/srv/damienwen/last-known-good` only after those checks pass, then
    clear the pending marker;
12. restore the persistent last-known-good release, or the preserved legacy
   service
   during the first migration, if production activation fails;
13. reconcile the persisted boot role and recover a pending activation before
    either website unit starts on boot;
14. retain the active release and four recent other known-good releases.

Keep production runs serial. Do not cancel a deployment while it is switching
releases.

The build job runs for every push to `main`. The deploy job additionally
requires an explicit `workflow_dispatch` from `main` and the repository
variable `DEPLOY_ENABLED` to equal `true`. Production environment secrets
belong only to that deploy job. Prefer a trusted reviewer other than the
release pusher, prevent self-review, and disallow bypass. If the user
explicitly confirms that this personal repository has no second reviewer, the
owner may be the required reviewer with self-review enabled; restrict that
environment to `main` and keep `DEPLOY_ENABLED=false` outside a supervised
deployment. Official Actions must be pinned to immutable full commit SHAs.

The Actions key is not a general VPS login key. Its dispatcher accepts only
`upload-archive <sha>`, `upload-checksum <sha>`, and `deploy <sha>`. Expected
GitHub secrets and first-migration requirements are documented in
`ops/README.md`. Never print secret values.

## Production checks

Run on the VPS:

```bash
systemctl status damienwen --no-pager
systemctl status damienwen-recover --no-pager
curl -I http://127.0.0.1:3000
readlink -f /srv/damienwen/current
readlink -f /srv/damienwen/last-known-good
journalctl -u damienwen -n 100 --no-pager
```

During the first migration, also inspect the preserved fallback when present:

```bash
systemctl status damienwen-legacy --no-pager
```

For Tunnel-only incidents:

```bash
systemctl status cloudflared --no-pager
journalctl -u cloudflared -n 100 --no-pager
```

Do not expose token-file contents.

## Recovery rules

- A failed build does not justify touching production.
- A failed preflight must not touch production.
- A failed or interrupted activation should restore the persistent
  `last-known-good` standalone release; during the first migration it should
  restore the preserved legacy service.
- Keep `damienwen-recover.service` enabled. Its once-per-boot check must run
  before both the managed and legacy website units.
- Preserve both fields in `activation-pending`: the exact verified candidate
  SHA and whether boot recovery should prefer `legacy` or retry `candidate`.
  Change the phase to `candidate` before retrying after a failed legacy
  fallback.
- Preserve the root-owned `boot-role` marker and both units' role
  `ExecCondition`. They make an interrupted enable/disable transition
  deterministic.
- Never clear `activation-pending` before the chosen production release and
  `last-known-good` state have been durably recorded.
- Resolve and record both the current and intended release before changing a
  symlink.
- Restart only after the target is known and complete.
- During the first migration, keep the legacy unit enabled and the managed unit
  disabled for reboot safety. Reverse that state only after the first managed
  release passes production health checks.
- Keep the active release plus the four recent known-good releases retained by
  the deployment script.
- Use `sudo /usr/local/sbin/damienwen-deploy <40-character-sha>` to reactivate
  a retained release through the same validated transaction.
