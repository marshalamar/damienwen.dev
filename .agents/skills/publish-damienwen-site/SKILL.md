---
name: publish-damienwen-site
description: Manage Damien Wen's damienwen.dev essay site. Use when Codex needs to create or edit an essay, add article images, preview and validate content, publish a tested release to the Ubuntu VPS through GitHub Actions, inspect a failed deployment, or roll the site back.
---

# Publish Damien Wen Site

Keep the site deliberately small: essays, images, and the existing article
reader. Do not add a CMS, database, tags, categories, authentication, or an
editor unless the user explicitly asks.

## Locate the project

Work only in the repository whose `package.json` name is `damienwen-dev`.
Preserve unrelated user changes. Treat `content/essays/` as the source of truth
for prose and `public/essays/` as the source of truth for article images.

Read [references/operations.md](references/operations.md) before publishing,
changing deployment infrastructure, diagnosing production, or rolling back.

## Add an essay

1. Inspect existing essays for numbering, metadata, voice, and image style.
2. Run:

   ```bash
   npm run essay:new -- <slug> "<title>"
   ```

   The command serializes concurrent creation attempts, creates or reuses the
   image directory first, and then exposes a complete MDX file atomically. Do
   not delete `.new-essay.lock` while another creation command may be running.

3. Edit the generated MDX file. Keep metadata minimal. Infer the slug and essay
   number from the filename; do not repeat them in metadata.
4. Put images under `public/essays/<slug>/` and reference them with absolute
   paths beginning `/essays/<slug>/`. Use the existing `<ArticleImage />` MDX
   component when an image belongs in the article body.
5. Keep copy natural and specific. Avoid explanatory filler, promotional
   language, redundant subtitles, and repeated author/location labels.
6. Run `npm run verify`. Fix actual failures before presenting or publishing.

Do not alter page components merely to publish ordinary prose. Add a reusable
MDX component only when the article genuinely needs a new visual form.

## Edit an essay

Change its MDX file and colocated image directory. Preserve its filename unless
the user explicitly wants the public URL changed. When changing a filename,
check every internal link and consider a redirect before publishing.

Run `npm run verify` after the edit.

## Preview

Use `npm run dev` and the exact local URL printed by the server. Reuse an
existing healthy preview when present. Perform browser inspection only when the
user asks to see or verify the rendered result.

## Publish

Pushing a reviewed commit to the production branch always builds and
smoke-tests the standalone server, but does not deploy or load production
secrets. Publishing to the VPS additionally means explicitly dispatching
`deploy.yml` from reviewed `main`. When the repository variable
`DEPLOY_ENABLED` is exactly `true` and the protected production environment is
approved, a separate clean runner downloads the tested artifact, uploads
through a forced SSH command, preflights an immutable release on
`127.0.0.1:3100`, switches the `current` symlink, restarts only
`damienwen.service`, and performs a production health check.

Before publishing:

1. Inspect the diff, branch, remote, and worktree status.
2. Confirm `npm run verify` succeeds.
3. Never commit `.env*`, SSH private keys, Cloudflare tokens, VPS passwords, or
   GitHub secrets.
4. Do not create a remote repository, change repository visibility, commit,
   push, or alter production unless the user has authorized that action.
5. Prefer an independent required reviewer with self-review disabled. For a
   sole-owner personal repository, use the owner as the required reviewer only
   after the user explicitly confirms that no second reviewer exists. In that
   mode, restrict the environment to `main`, allow self-review, and keep
   `DEPLOY_ENABLED=false` whenever no deployment is actively being supervised.
   If the variable is absent or false, a push validates the site but
   deliberately skips the VPS deployment.
6. After the pushed build succeeds, explicitly dispatch `deploy.yml` from
   `main`; do not bypass the environment approval.
7. Immediately after dispatch, tell the user that the deploy job is waiting on
   the protected GitHub `production` environment and that they must approve it
   in the GitHub UI. In the current sole-owner setup the user is the required
   reviewer; the agent cannot approve. Give them the run URL (for example from
   `gh run list --workflow=deploy.yml --limit 1` or `gh run watch`) and wait
   for their approval before treating the release as in progress. Do not
   silently poll without telling them what is blocked.

Do not edit files directly in the active VPS release. Do not restart
`cloudflared` during an ordinary article release.

## Diagnose and roll back

Identify which layer failed before changing anything:

- build or content validation: inspect the GitHub Actions run;
- release switch or process startup: inspect `damienwen.service`;
- local origin: test `http://127.0.0.1:3000`;
- public routing: inspect Cloudflare Tunnel separately.

Keep the website bound to `127.0.0.1:3000`. Port `443` belongs to another
service and is outside this workflow.

Use the versioned release tooling in `ops/` for rollback. Never delete all old
releases or replace the `current` symlink without first resolving its target.
