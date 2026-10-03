# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The `openclaw` runtime for [language-operator](https://github.com/language-operator/language-operator). It does **not** build openclaw. The agent's main container runs the upstream `ghcr.io/openclaw/openclaw` image unchanged. This repo ships two things:

- **An init-container seeder** (`ghcr.io/language-operator/openclaw-adapter`). Before openclaw starts, it translates the operator-injected `/etc/agent/config.yaml` into openclaw's own config under `/workspace/.openclaw`.
- **A Helm chart** that registers the cluster-scoped `openclaw` `LanguageAgentRuntime`, which wires the two images together.

The seeder writes openclaw's config format, so an upstream openclaw release can break agents with no change here. That's why the upstream image is pinned.

## Layout

- `seed-config.mjs`: the whole seeder (Node, one dependency: `yaml`).
  - On first boot it writes `openclaw.json` (gateway, `mcp.servers`, `models.providers`).
  - On later boots it rewrites only the operator-managed sections (gateway, `mcp.servers`, and its own model providers, recognised by their `apiKey`: `${MODEL_API_KEY}` when the operator injects the agent's gateway key, else the `sk-langop-proxy` placeholder) and keeps the rest of the user's runtime state. It also clears a primary model that no longer exists.
  - It always overwrites `AGENTS.md` and `SOUL.md` from the personas.
  - Model config comes from `config.yaml`, or from the `MODEL_ENDPOINT`/`LLM_MODEL` env vars if `config.yaml` has none.
- `test.sh`: shell tests that run *inside* the built image, one scenario per `--- Test N` block. Add a scenario for any new seed behaviour.
- `Dockerfile`: `node:24-alpine` + `seed-config.mjs` + `test.sh`.
- `chart/`: `templates/languageagentruntime.yaml` is the runtime preset. `values.yaml` pins the upstream `image.tag` and this repo's `adapter.image.tag`.

## Testing

Mirror the PR CI jobs in `.github/workflows/test.yaml`:

- `image-test`: `make test`. Builds the adapter image and runs `/app/test.sh` inside it (one scenario per `--- Test N` block against `seed-config.mjs`). Add a scenario to `test.sh` for any new seed behaviour.
- `chart-lint`: `helm lint chart && helm template openclaw chart >/dev/null`
- There is no JS linter.
- The PR title must be a conventional commit (`feat:`, `fix:`, `chore:`, `docs:`, `test:`).

## Versioning and releases

- One version, in lockstep: `chart/Chart.yaml` `version` and `appVersion`, `adapter.image.tag` in `chart/values.yaml`, and the git tag `vX.Y.Z`.
- `/release major|minor|patch` bumps the version, tags, and pushes after you confirm.
- Pushing the tag publishes the image (`build-image.yaml`) and the chart (`release-chart.yaml`). The chart is published **only** on tags, and the workflow refuses to overwrite a published version. Merging to `main` publishes no chart, but it does push the `latest`/`main`/`sha-` image tags.
- `language-operator`'s `language-operator-runtimes` umbrella chart pins this chart's version. Treat a published version as immutable.
- The upstream openclaw `image.tag` is not this repo's version. Move it with `/update-dependencies`, never with `/release`.

## Workflow

`/iterate [#N] [--auto]` handles **one** issue, from selection to a merged PR and a closed issue, then stops. For continuous work, use `/loop /iterate`. Work happens inside a git worktree under `.claude/worktrees/`.

It comes from the shared `langop` plugin in [`language-operator/skills`](https://github.com/language-operator/skills), pinned to a tag in `.claude/settings.json`. There is no copy in this repo any more. `/iterate` and `/langop:iterate` both run it. The skill has nothing repo-specific in it: it reads `## Testing` above to learn how to test a change here, so keep that section accurate.

Interactive sessions need no install step: the plugin loads at the pinned tag once the folder is trusted. Non-interactive runs (`claude -p`, scheduled or in-cluster agents) have no trust dialog, so they need this once, with the tag the repo pins:

```bash
claude plugin marketplace add 'language-operator/skills#v0.1.0'
claude plugin install langop@language-operator --scope project
```

Two things to avoid:
- A marketplace add without `#<tag>` follows `main` instead of the pin.
- `--scope project` on the *marketplace* add rewrites `.claude/settings.json` and drops its `ref`.

To take a newer release, change `ref` in `.claude/settings.json`. Machine-specific settings go in `.claude/settings.local.json` (git-ignored).
