# openclaw-adapter

The **openclaw** runtime for the [Language Operator](https://github.com/language-operator/language-operator),
running as a native Kubernetes workload.

This repository is self-contained — it builds the adapter init image and the
Helm chart that registers the `openclaw` `LanguageAgentRuntime`. The main
container runs the upstream `ghcr.io/openclaw/openclaw` image; this repo only
provides the init/adapter that translates the operator's config into openclaw's
native format.

## What's here

- **Adapter image** (`ghcr.io/language-operator/openclaw-adapter`) — an init
  container that translates the operator's `/etc/agent/config.yaml` into
  openclaw's provider config under `/workspace/.openclaw`.
- **Chart** (`chart/`) — renders the cluster-scoped `openclaw`
  `LanguageAgentRuntime`. Published to `oci://ghcr.io/language-operator/charts/openclaw`.

## Install

Prerequisite: the [`language-operator`](https://github.com/language-operator/language-operator)
chart must be installed first — it provides the `LanguageAgentRuntime` CRD.

```bash
helm install openclaw oci://ghcr.io/language-operator/charts/openclaw \
  --namespace language-operator
```

Then reference it from a `LanguageAgent`:

```yaml
apiVersion: langop.io/v1alpha1
kind: LanguageAgent
metadata:
  name: my-agent
spec:
  runtime: openclaw
```

## Development

```bash
make build      # docker build -t ghcr.io/language-operator/openclaw-adapter:latest .
make test       # build, then run the in-image smoke tests (/app/test.sh)
make publish    # build and push the image to ghcr.io

helm lint chart
helm template openclaw chart
```

## CI

- `build-image.yaml` — builds and pushes the adapter image to `ghcr.io` on push to `main` and `v*` tags.
- `release-chart.yaml` — packages `chart/` and pushes it to `oci://ghcr.io/language-operator/charts`.
- `test.yaml` — builds the image, runs the smoke tests, and lints/templates the chart on every PR.
