---
description: Bring every pinned upstream dependency up to date, with an audit trail
argument-hint: "[all|openclaw|node|actions] (default: all)"
allowed-tools: Bash(git:*), Bash(gh:*), Bash(npm:*), Bash(curl:*), Bash(jq:*), Bash(docker:*), Bash(helm:*), Bash(make:*), Bash(grep:*), Read, Edit, Grep
---

Update the upstream dependencies of `openclaw-adapter`. Scope: **$ARGUMENTS** (empty means `all`).

The point is not only that versions move but that the move is **recorded**: old version, new version, digest, and what changed. The PR is the audit trail. A bump with no evidence behind it is worse than no bump, because it looks reviewed.

## The dependency surface

**1. The upstream openclaw image.** This is the main container, and the one that matters most here: `seed-config.mjs` writes openclaw's own config format (`openclaw.json`, `mcp.servers`, gateway settings), so an upstream change to that format breaks agents without any change in this repo.

Pinned in one place: `chart/values.yaml` `image.tag` (`ghcr.io/openclaw/openclaw`).

**2. The adapter's Node base image.** `Dockerfile` `FROM node:24-alpine`.

> The `yaml` npm package is installed in the `Dockerfile` with a bare `npm install yaml`, which ignores `package.json` and `package-lock.json`, so every image build takes whatever `yaml` is current. Pinning it is a change in behaviour, not a version bump. Raise it as its own decision. If it is still unpinned when you run this, say so in the report.

**3. GitHub Actions.** Across `.github/workflows/{test,build-image,release-chart}.yaml`: `actions/checkout`, `docker/setup-buildx-action`, `docker/login-action`, `docker/metadata-action`, `docker/build-push-action`, `azure/setup-helm`.

`adapter.image.tag` in `chart/values.yaml` is **not** an upstream dependency. It is this repo's own release version, and `/release` moves it.

## Rules

- **Never pin `latest`.** Only released versions.
- **Read upstream release notes before moving openclaw.** Look for anything about the config file, `mcp`, `gateway`, auth or the state dir, and check it against what `seed-config.mjs` writes.
- **Don't unpin anything to make an update easier.** If a pin gets in the way, report that as the finding.

## Steps

Stop and report if any precondition fails.

**1. Preconditions.** On `main`, working tree clean, `git fetch origin`, `main` not behind `origin/main`. Then `git checkout -b chore/update-dependencies`.

**2. Record the current state.**

```bash
grep -n -A2 '^image:' chart/values.yaml
grep -n '^FROM' Dockerfile
grep -rn 'uses: .*@' .github/workflows/
```

**3. Discover the latest versions.**

openclaw: take the release GitHub marks as `Latest`. Upstream cuts backport releases on older trains (e.g. `2026.8.x` published after `2026.9.x`), so don't just take the newest by date:

```bash
gh release list -R openclaw/openclaw --limit 10
T=$(curl -s "https://ghcr.io/token?scope=repository:openclaw/openclaw:pull&service=ghcr.io" | jq -r .token)
curl -sI -H "Authorization: Bearer $T" \
  -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://ghcr.io/v2/openclaw/openclaw/manifests/<YYYY.M.N>" | grep -i docker-content-digest
```

The image tag has no leading `v` (release `v2026.9.7` is image `2026.9.7`). Confirm that the manifest request returns 200 before pinning it.

Node: the current `24-alpine` (stay on the 24 LTS line unless asked). Actions: each action's latest major via `gh release list -R <owner>/<repo> --limit 3`.

**4. Apply the changes**, then validate:

```bash
helm lint chart && helm template openclaw chart >/dev/null
make test
```

**5. Commit and open a PR** (`chore: update dependencies`). The body is the audit trail. For each dependency it gives a table row (old → new, with the digest for images) and the release notes you checked, plus any note on the openclaw config format. It also restates the unpinned `yaml` finding if it still applies.
