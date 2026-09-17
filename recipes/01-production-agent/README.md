# 01 - Minimal production agent

A small, safe-by-default OpenTelemetry Collector agent that accepts OTLP traces, metrics and logs over gRPC and HTTP, protects itself against memory exhaustion, enriches data with host attributes and forwards everything over compressed OTLP/gRPC to your gateway or backend. The outcome is a node-local agent you can deploy next to applications without surprises: bounded memory, retries plus an in-memory queue during backend blips, and no debug output or public admin ports.

## When to use

- You need a first collector in front of your SDKs (VM, Docker host, sidecar or DaemonSet).
- You want one hop that batches and compresses before data leaves the host.
- You want a known-good baseline to extend with the other recipes.

Not for: tail sampling, load balancing or persistent queuing (covered by recipes 06, 07 and 14 in the [full pack](https://fractaltechware.gumroad.com/l/otel-collector-recipes?utm_source=github&utm_medium=readme&utm_campaign=free-repo)).

## How it works

```
otlp (gRPC :4317, HTTP :4318)
  -> memory_limiter -> resource_detection -> batch
  -> otlp_grpc (gzip, retry, sending_queue)
```

- `memory_limiter` is first so data is refused (receivers return a retryable error to SDKs) before the process can OOM. Nothing upstream of it is protected.
- `resource_detection` (`env`, `system`) adds `host.name`, `os.type` and anything in `OTEL_RESOURCE_ATTRIBUTES`; `override: false` keeps attributes the SDK already set, such as `service.name`.
- `batch` is last so it batches the final, enriched data; bigger batches mean fewer requests and better gzip ratios.
- The same processor chain is used for all three signals, so behaviour is consistent.

## Quickstart

1. `cp .env.example .env`
2. Edit `.env`: set `OTLP_EXPORT_ENDPOINT` (host:port). Leave `OTLP_EXPORT_INSECURE=false` unless the hop is plaintext inside a trusted network.
3. `docker compose up -d`
4. Verify: `curl -s http://127.0.0.1:13133/` (health check) and `docker compose logs -f otelcol` (look for `Everything is ready`).
5. Point SDKs at `http://127.0.0.1:4318` (HTTP) or `127.0.0.1:4317` (gRPC).
6. To see data flowing, temporarily add `--config=/etc/otelcol/debug.overlay.yaml` to the compose `command`, then remove it again.

Validate before deploying:

```
docker run --rm -v "$PWD:/cfg:ro" -e OTLP_EXPORT_ENDPOINT=gateway:4317 \
  otel/opentelemetry-collector-contrib:0.161.0 validate --config=/cfg/config.yaml
```

Run the binary / other platforms: `OTLP_EXPORT_ENDPOINT=gateway:4317 otelcol-contrib --config=config.yaml` (add `--config=debug.overlay.yaml` for debugging).

## Configuration (environment variables)

| Variable | Default | Required | Purpose |
|---|---|---|---|
| `OTLP_EXPORT_ENDPOINT` | none | Yes | host:port of your gateway or backend |
| `OTLP_EXPORT_INSECURE` | `false` | No | `true` only for plaintext inside a trusted network |
| `OTEL_LISTEN_ADDR` | `localhost` | No | Receiver bind address (`0.0.0.0` in containers, pod IP in Kubernetes) |
| `OTEL_HEALTH_ADDR` | `localhost` | No | health_check bind address (pod IP in Kubernetes so probes work) |
| `OTEL_TELEMETRY_ADDR` | `localhost` | No | Bind address of the collector's own `/metrics` on port 8888 |
| `OTEL_LOG_LEVEL` | `info` | No | Collector log level |

## Tunables

| Setting (YAML path) | Value shipped | When to change |
|---|---|---|
| `processors.memory_limiter.limit_percentage` | `80` | Lower if other processes share the cgroup; always pair with a memory limit and `GOMEMLIMIT` |
| `processors.memory_limiter.spike_limit_percentage` | `20` | Raise for very bursty traffic |
| `receivers.otlp.protocols.grpc.max_recv_msg_size_mib` | `16` | Raise if SDKs send large batches and get `ResourceExhausted` |
| `processors.batch.send_batch_size` / `send_batch_max_size` | `2048` / `4096` | Lower if the backend rejects large requests |
| `processors.batch.timeout` | `5s` | Lower for fresher data, raise for better compression |
| `exporters.otlp_grpc.retry_on_failure.max_elapsed_time` | `300s` | How long a backend outage is survived before data is dropped |
| `exporters.otlp_grpc.sending_queue.queue_size` | `1000` (batches) | Raise for longer outages; costs memory |
| `exporters.otlp_grpc.sending_queue.num_consumers` | `10` | Raise if the queue grows while the backend is healthy |

## Pitfalls

- `limit_percentage` is computed from the cgroup memory limit. Without a container limit it is relative to host memory and will not protect you. Compose sets `mem_limit: 512m` and `GOMEMLIMIT: 400MiB` (about 80%).
- The queue is in memory: a restart during an outage loses queued data. Use a persistent queue (recipe 14 in the full pack) if that matters.
- Binding to `localhost` inside a container makes receivers unreachable from other containers; compose sets `OTEL_LISTEN_ADDR=0.0.0.0` for that reason and publishes ports on `127.0.0.1` only.
- Multiple `--config` files deep-merge maps but REPLACE lists. That is why `debug.overlay.yaml` repeats `[otlp_grpc, debug]` for every pipeline; an overlay that lists only `[debug]` silently stops exporting.
- `detailed` debug verbosity prints full payloads, including any PII, and is expensive at volume. Remove the overlay after debugging.
- A literal `$` in the config must be written `$$`; a single `$` is treated as an environment variable reference.
- Component names are the 0.161.0 snake_case ones (`otlp_grpc`, `resource_detection`). Old aliases such as `otlphttp` or `resourcedetection` still load but log deprecation warnings.

## Security notes

- Receivers, health_check and internal telemetry default to `localhost`; in Kubernetes bind to the pod IP, not `0.0.0.0` on a host network.
- Never publish port 13133 or 8888 outside the host/pod. Compose publishes only on `127.0.0.1`.
- `tls.insecure` defaults to `false`; plaintext has to be opted into explicitly.
- No secrets live in YAML; endpoints come from environment variables. Do not commit `.env`.
- Compose runs as uid 10001 with a read-only root filesystem, `cap_drop: [ALL]` and `no-new-privileges`.

## What the automated test proves

These behavioural tests run in the end-to-end suite of the [full pack](https://fractaltechware.gumroad.com/l/otel-collector-recipes?utm_source=github&utm_medium=readme&utm_campaign=free-repo) against this exact config. This free repo's CI runs `otelcol-contrib validate` on every config.

- A trace, a log record and a metric sent over OTLP/HTTP all reach the export destination, and the sent trace ID arrives intact.
- `resource_detection` adds `host.name`, and `override: false` keeps the SDK-set `service.name` (`checkout`).
- The internal telemetry port 8888 is NOT reachable from outside the container when `OTEL_TELEMETRY_ADDR` is left at its localhost default.
- With `debug.overlay.yaml` merged, the debug exporter prints the data to the collector log AND the normal exporter still receives it (list replacement handled correctly).
- Every recipe is also run through `otelcol-contrib validate` and started hardened (uid 10001, read-only rootfs, cap-drop ALL); the test fails on any deprecation warning or error-level line in the logs.

## Troubleshooting

- SDKs get `connection refused` -> receiver bound to `localhost` inside a container -> set `OTEL_LISTEN_ADDR=0.0.0.0` (containers) or the pod IP.
- Logs show `data refused due to high memory usage` -> memory_limiter is protecting the process -> raise the container memory limit and `GOMEMLIMIT` together, or scale out.
- Export fails with TLS handshake / `first record does not look like a TLS handshake` -> TLS mismatch with the backend -> enable TLS on the backend, or set `OTLP_EXPORT_INSECURE=true` only for a trusted plaintext hop.
- `sending queue is full` in logs -> backend slow or down longer than the queue can absorb -> fix the backend, raise `queue_size`/`num_consumers`, or add a persistent queue (`file_storage` + `sending_queue.storage`).
