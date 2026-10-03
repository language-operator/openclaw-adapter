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

## Commands

```bash
make test                                          # build the image, run /app/test.sh in it
helm lint chart && helm template openclaw chart    # chart checks
```

These mirror the PR CI jobs `image-test` and `chart-lint` in `.github/workflows/test.yaml`. There is no JS linter.

## Versioning and releases

- One version, in lockstep: `chart/Chart.yaml` `version` and `appVersion`, `adapter.image.tag` in `chart/values.yaml`, and the git tag `vX.Y.Z`.
- `/release major|minor|patch` bumps the version, tags, and pushes after you confirm.
- Pushing the tag publishes the image (`build-image.yaml`) and the chart (`release-chart.yaml`). The chart is published **only** on tags, and the workflow refuses to overwrite a published version. Merging to `main` publishes no chart, but it does push the `latest`/`main`/`sha-` image tags.
- `language-operator`'s `language-operator-runtimes` umbrella chart pins this chart's version. Treat a published version as immutable.
- The upstream openclaw `image.tag` is not this repo's version. Move it with `/update-dependencies`, never with `/release`.

## Workflow

- `/iterate [#N]` takes one issue through worktree → PR → green CI → merge → close.
- The scripts in `.claude/commands/iterate/`, and everything in `iterate.md` except the `allowed-tools` build tools and `## Testing`, are copied verbatim from language-operator (canonical per language-operator#932). Change them there, not here.
