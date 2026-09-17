# OpenTelemetry Collector Recipes

**Production-ready OpenTelemetry Collector configs — tested, pinned to 0.161.0.**

[![validate](https://github.com/Fractal-Techware/opentelemetry-collector-recipes/actions/workflows/validate.yml/badge.svg)](https://github.com/Fractal-Techware/opentelemetry-collector-recipes/actions/workflows/validate.yml)
[![otelcol-contrib](https://img.shields.io/badge/otelcol--contrib-0.161.0-425cc7?logo=opentelemetry)](https://github.com/open-telemetry/opentelemetry-collector-releases/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Docker Compose](https://img.shields.io/badge/deploy-Docker%20Compose-2496ED?logo=docker&logoColor=white)](#quickstart)

Copy-paste OpenTelemetry Collector (`otelcol-contrib`) configurations for a production agent,
file logs to Grafana Loki over OTLP, and basic PII redaction with OTTL. Every config passes
`otelcol-contrib validate` on the pinned version in CI, uses the current snake_case component
names (no deprecation warnings), keeps secrets out of YAML, and ships with a hardened Docker
Compose file (non-root, read-only root filesystem, no capabilities, ports on `127.0.0.1` only).

Maintained by [Fractal Techware](https://fractaltechware.gumroad.com/?utm_source=github&utm_medium=readme&utm_campaign=free-repo).
MIT licensed: use it at work, fork it, ship it.

## Recipes

| Recipe | What you get | Signals | Backend |
|---|---|---|---|
| [01 - Production agent](recipes/01-production-agent/) | OTLP gRPC/HTTP in, `memory_limiter`, `resource_detection`, `batch`, gzip OTLP out with retry and sending queue. Debug output as an opt-in overlay. | traces, metrics, logs | any OTLP gateway or vendor |
| [03 - File logs to Loki](recipes/03-logs-to-loki/) | `file_log` with JSON + plain-text severity parsing, restart-safe checkpoints, `service_name` label, native Loki OTLP endpoint. | logs | Grafana Loki 3.x |
| [PII redaction (basic)](snippets/pii-redaction-basic/) | OTTL `transform` processor that masks emails and card numbers and deletes `Authorization` / `Cookie` / API-key attributes. Basic version, gaps documented. | traces, logs | any |

Each recipe folder contains `config.yaml`, `compose.yaml`, `.env.example` and a README covering
when to use it, how it works, every environment variable, tunables, pitfalls, security notes and
troubleshooting.

## Quickstart

```bash
git clone https://github.com/Fractal-Techware/opentelemetry-collector-recipes.git
cd opentelemetry-collector-recipes/recipes/01-production-agent

cp .env.example .env            # set OTLP_EXPORT_ENDPOINT=your-gateway:4317
docker compose up -d
curl -s http://127.0.0.1:13133/ # health check
```

Point your OpenTelemetry SDKs at `http://127.0.0.1:4318` (OTLP/HTTP) or `127.0.0.1:4317` (OTLP/gRPC).

Validate a config before deploying it:

```bash
docker run --rm -v "$PWD:/cfg:ro" -e OTLP_EXPORT_ENDPOINT=gateway:4317 \
  otel/opentelemetry-collector-contrib:0.161.0 validate --config=/cfg/config.yaml
```

Or validate everything in the repo: `./scripts/validate.sh`.

Not using Docker? The configs are plain collector YAML driven by environment variables:
`OTLP_EXPORT_ENDPOINT=gateway:4317 otelcol-contrib --config=config.yaml`.

## Common OpenTelemetry Collector mistakes these configs avoid

- **`memory_limiter` in the wrong place, or without a memory limit.** It must be the first processor, and its percentages are relative to the cgroup limit. The compose files set `mem_limit` and `GOMEMLIMIT` together.
- **`batch` before enrichment.** Batching goes last so it batches the final data and compresses better.
- **Deprecated component names.** Old configs use `otlphttp`, `resourcedetection`, `filelog` and log warnings on 0.161.0. These use `otlp_http`, `resource_detection`, `file_log`.
- **Receivers bound to `0.0.0.0` on the host.** Everything defaults to `localhost`; containers opt in, and Docker publishes on `127.0.0.1` only.
- **The debug exporter left on in production.** It is an overlay you add temporarily, not part of the base config.
- **Overlays that silently stop exporting.** Multiple `--config` files deep-merge maps but *replace lists*; the debug overlay repeats the full exporter list.
- **Plaintext by accident.** `tls.insecure` defaults to `false`; plaintext is an explicit opt-in.
- **Unescaped `$` in regexes.** The collector reads `$` as an env var reference; `$$` is used where a literal one is needed.
- **Log checkpoints on ephemeral storage.** `file_storage` must persist, or restarts produce duplicate logs or gaps.
- **`/v1/logs` appended twice to the Loki URL.** The OTLP/HTTP exporter adds it; the endpoint is the `/otlp` base.
- **Loki's removed `loki` exporter.** Loki 3.x ingests native OTLP, so that is the path used here.
- **Redaction after export.** PII processing runs before `batch` and before every exporter.

## Want all 16 recipes?

This repo is a free sample of the **OpenTelemetry Collector Production Recipes** pack. The paid
tiers run every recipe hardened in Docker and assert on what actually comes out: tail sampling keeps
errors and slow traces, load balancing never splits a trace, the persistent queue survives a
backend outage *and* a restart, mTLS rejects a certificate from the wrong CA.

| | Free (this repo) | Starter | Pro | Studio |
|---|:-:|:-:|:-:|:-:|
| Price | $0 | $19 | $49 | $99 |
| Production agent, logs to Loki | Yes | Yes | Yes | Yes |
| Host metrics to Prometheus, traces to Tempo/Jaeger, Prometheus scrape to OTLP | - | Yes | Yes | Yes |
| 5-minute Docker Compose quickstart (telemetrygen, agent, backend) | - | Yes | Yes | Yes |
| PII redaction | Basic snippet | - | Hardened, tested | Hardened, tested |
| Load-balanced gateway with tail sampling | - | - | Yes | Yes |
| Cost reduction, Kubernetes attributes, span metrics & service graph | - | - | Yes | Yes |
| Multi-tenant routing, GenAI/LLM telemetry | - | - | Yes | Yes |
| Persistent queue, mTLS agent-to-gateway, self-monitoring + alert rules | - | - | Yes | Yes |
| Helm values (official chart), OpenTelemetry Operator CRs | - | - | - | Yes |
| One-command lab: collector + Prometheus + Loki + Tempo + Grafana | - | - | - | Yes |
| Sizing & tuning guide, client-use license | - | - | - | Yes |
| Recipes | 2 + snippet | 5 | 16 | 16 |

[**See the full pack on Gumroad**](https://fractaltechware.gumroad.com/l/otel-collector-recipes?utm_source=github&utm_medium=readme&utm_campaign=free-repo)

## Compatibility

| Component | Version |
|---|---|
| OpenTelemetry Collector Contrib | `otel/opentelemetry-collector-contrib:0.161.0` |
| Grafana Loki (recipe 03) | 3.0 or newer (native OTLP endpoint) |
| Docker Compose | v2 |

Other collector versions may work, but component names and defaults change between releases.
Validate before upgrading.

## FAQ

**Can I use these with a vendor backend (Grafana Cloud, Honeycomb, Datadog, New Relic, Elastic...)?**
Yes. Recipe 01 exports OTLP/gRPC to any OTLP endpoint. Add the vendor's auth header under
`exporters.otlp_grpc.headers`, with the key taken from an environment variable.

**Do these work in Kubernetes?**
The configs do. Bind receivers and `health_check` to the pod IP (`OTEL_LISTEN_ADDR`,
`OTEL_HEALTH_ADDR`) instead of `0.0.0.0` on a host network. Kubernetes metadata enrichment,
Helm values and Operator CRs are in the paid tiers.

**Is the PII snippet enough for GDPR/PCI?**
No. It is a starting point with documented gaps. Treat any collector-side redaction as defence in
depth, not as your only control.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © Fractal Techware. OpenTelemetry is a trademark of The Linux Foundation; this
project is not affiliated with or endorsed by the OpenTelemetry project.
